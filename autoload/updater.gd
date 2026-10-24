extends Node
## In-game updates. Shortly after launch (and every few hours while playing)
## it asks GitHub for the newest Weed World release. When one is newer than
## this build it offers it on the update card (ui/update/update_prompt.gd),
## downloads this platform's file with live progress, checks its SHA-256
## against the one GitHub publishes, then installs it:
## - Android: hands the APK to the system installer through Godot's built-in
##   FileProvider (OS.shell_open), after walking the player through the
##   one-time "allow installs from this app" switch.
## - Windows: swaps the new WeedWorld.exe in beside the running one and
##   relaunches (UpdateFeed.swap_in_zip).
## Anything else, or anything that fails, falls back to the download page.
## Only exported builds check; the editor and headless runs never do.

signal state_changed(state: int)
## A player who just updated: shown once as a "welcome to vX" note.
signal updated(from_version: String, to_version: String)
## The HUD's "Check for updates" was pressed.
signal card_requested

enum State { IDLE, CHECKING, UP_TO_DATE, AVAILABLE, DOWNLOADING, VERIFYING, READY, NEEDS_PERMISSION, INSTALLING, APPLYING, FAILED }

const DIR := "user://updates"
const SETTINGS := "user://updater.cfg"
const FIRST_CHECK_DELAY := 4.0
const RECHECK_EVERY := 3.0 * 3600.0
const ANDROID_O := 26

var state: int = State.IDLE
## The offered release: {version, tag, page, asset{name,url,size,sha256}, notes, published}.
var release: Dictionary = {}
var current_version := ""
var plat := ""
var error_text := ""
## True when the player asked for this check (the card then reports "up to date").
var manual_check := false
var downloaded := 0
var total := 0
var speed := 0.0       ## bytes per second, smoothed
var enabled := false

var _feed: HTTPRequest
var _dl: HTTPRequest
var _next_check := FIRST_CHECK_DELAY
var _speed_bytes := 0
var _speed_clock := 0.0
var _verify_task := -1
var _verify_result := ""
var _quiet_verify := false
var _before_check: int = State.IDLE
var _apply_task := -1
var _apply_result := ""
var _apply_leftovers: Array = []
var _cleanup_tries := 0
var _cleanup_clock := 3.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	current_version = str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	plat = UpdateFeed.platform()
	enabled = OS.has_feature("template") and DisplayServer.get_name() != "headless" \
			and not OS.get_cmdline_user_args().has("--no-update-check")
	if not enabled:
		set_process(false)
		return
	_feed = HTTPRequest.new()
	_feed.use_threads = true
	_feed.timeout = 20.0
	_feed.request_completed.connect(_on_feed)
	add_child(_feed)
	_dl = HTTPRequest.new()
	_dl.use_threads = true
	_dl.download_chunk_size = 1 << 18
	_dl.request_completed.connect(_on_downloaded)
	add_child(_dl)
	_note_version()
	_tidy_downloads()
	add_child(load("res://ui/update/update_prompt.gd").new(self))


func _process(delta: float) -> void:
	if state in [State.IDLE, State.UP_TO_DATE]:
		_next_check -= delta
		if _next_check <= 0.0:
			check()
	elif state == State.DOWNLOADING:
		downloaded = _dl.get_downloaded_bytes()
		var body := _dl.get_body_size()
		if body > 0:
			total = body
		_speed_clock += delta
		if _speed_clock >= 0.5:
			var rate := (downloaded - _speed_bytes) / _speed_clock
			speed = rate if speed <= 0.0 else lerpf(speed, rate, 0.35)
			_speed_bytes = downloaded
			_speed_clock = 0.0
	elif state == State.VERIFYING and _verify_task >= 0 and WorkerThreadPool.is_task_completed(_verify_task):
		WorkerThreadPool.wait_for_task_completion(_verify_task)
		_verify_task = -1
		_on_verified()
	elif state == State.APPLYING and _apply_task >= 0 and WorkerThreadPool.is_task_completed(_apply_task):
		WorkerThreadPool.wait_for_task_completion(_apply_task)
		_apply_task = -1
		_on_applied()

	# The .old files from a Windows update unlock once the old game has quit.
	if _cleanup_tries > 0:
		_cleanup_clock -= delta
		if _cleanup_clock <= 0.0:
			_cleanup_clock = 5.0
			_cleanup_tries -= 1
			_cleanup_leftovers()


func _notification(what: int) -> void:
	# Back from Android's "install unknown apps" screen: carry on by itself.
	if what in [NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN]:
		if state == State.NEEDS_PERMISSION and can_install_packages():
			install()


# ---------------------------------------------------------------------------
# Public API (driven by the update card and the HUD)

func progress() -> float:
	return clampf(float(downloaded) / float(total), 0.0, 1.0) if total > 0 else 0.0


func eta() -> float:
	return (total - downloaded) / speed if speed > 1.0 and total > 0 else -1.0


## Asks GitHub for the newest release. A manual check reports back even when
## there is nothing new.
func check(manual := false) -> void:
	if not enabled or state in [State.CHECKING, State.DOWNLOADING, State.VERIFYING, State.APPLYING]:
		return
	manual_check = manual
	_next_check = RECHECK_EVERY
	_before_check = state
	_set_state(State.CHECKING)
	var err := _feed.request(UpdateFeed.FEED_URL, _headers())
	if err != OK:
		_check_failed("Couldn't reach the update server.")


func can_self_install() -> bool:
	return plat in ["android", "windows"] and not release.get("asset", {}).is_empty()


## Downloads the offered file (or reuses an earlier, intact download).
func download() -> void:
	if release.is_empty():
		return
	if not can_self_install():
		open_release_page()
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := _file_path()
	if FileAccess.file_exists(path):
		_verify(path)
		return
	downloaded = 0
	total = int(release.asset.size)
	speed = 0.0
	_speed_bytes = 0
	_speed_clock = 0.0
	_dl.download_file = path + ".part"
	if FileAccess.file_exists(_dl.download_file):
		DirAccess.remove_absolute(_dl.download_file)
	var err := _dl.request(release.asset.url, _headers())
	if err != OK:
		_fail("The download couldn't start.")
		return
	_set_state(State.DOWNLOADING)


func cancel() -> void:
	if state == State.DOWNLOADING:
		_dl.cancel_request()
		DirAccess.remove_absolute(_dl.download_file)
		_set_state(State.AVAILABLE)


## Android: open the system installer. Windows: swap and relaunch.
func install() -> void:
	if state not in [State.READY, State.NEEDS_PERMISSION, State.INSTALLING, State.FAILED]:
		return
	if not FileAccess.file_exists(_file_path()):
		download()
		return
	match plat:
		"android":
			if not can_install_packages():
				_set_state(State.NEEDS_PERMISSION)
				return
			var err := OS.shell_open(ProjectSettings.globalize_path(_file_path()))
			if err != OK:
				_fail("Android wouldn't open the installer.")
				return
			_set_state(State.INSTALLING)
		"windows":
			_set_state(State.APPLYING)
			_apply_result = ""
			_apply_leftovers = []
			_apply_task = WorkerThreadPool.add_task(_apply_windows, true, "Install update")


## Android 8+: has the player let Weed World install apps? Unknown (no
## runtime access) counts as yes, so the system installer asks instead.
func can_install_packages() -> bool:
	var activity = _android_activity()
	if activity == null:
		return true
	var version = JavaClassWrapper.wrap("android.os.Build$VERSION")
	if version == null or int(version.SDK_INT) < ANDROID_O:
		return true
	var pm = activity.getPackageManager()
	if pm == null:
		return true
	var allowed = pm.canRequestPackageInstalls()
	if JavaClassWrapper.get_exception() != null:
		return true
	return bool(allowed)


## Opens Android's "Install unknown apps" switch for Weed World. Falls back to
## the installer itself (which links to the same switch) if that fails.
func open_install_settings() -> void:
	var activity = _android_activity()
	var ok := false
	if activity != null:
		var intent_class = JavaClassWrapper.wrap("android.content.Intent")
		var uri_class = JavaClassWrapper.wrap("android.net.Uri")
		if intent_class != null and uri_class != null:
			var intent = intent_class.Intent("android.settings.MANAGE_UNKNOWN_APP_SOURCES")
			if intent != null:
				intent.setData(uri_class.parse("package:" + str(activity.getPackageName())))
				intent.addFlags(0x10000000)   # FLAG_ACTIVITY_NEW_TASK
				activity.startActivity(intent)
				ok = JavaClassWrapper.get_exception() == null
	if not ok:
		var err := OS.shell_open(ProjectSettings.globalize_path(_file_path()))
		if err == OK:
			_set_state(State.INSTALLING)


func open_release_page() -> void:
	OS.shell_open(str(release.get("page", UpdateFeed.RELEASES_URL)))


## Opens the update card: the offer if there is one, otherwise a fresh check.
func request_card() -> void:
	card_requested.emit()


## "Try again" after anything went wrong picks up at the right step.
func retry() -> void:
	if release.is_empty():
		check(true)
	elif FileAccess.file_exists(_file_path()):
		_set_state(State.READY)
		install()
	else:
		download()


# ---------------------------------------------------------------------------

func _set_state(s: int) -> void:
	state = s
	state_changed.emit(s)


func _headers() -> PackedStringArray:
	return PackedStringArray(["User-Agent: WeedWorld/%s (%s)" % [current_version, plat], "Accept: application/vnd.github+json"])


func _android_activity():
	if plat != "android" or not Engine.has_singleton("AndroidRuntime"):
		return null
	return Engine.get_singleton("AndroidRuntime").getActivity()


func _file_path() -> String:
	var asset: Dictionary = release.get("asset", {})
	return DIR.path_join(str(asset.get("name", "update.bin")).validate_filename())


func _on_feed(result: int, code: int, _headers_in: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_check_failed("No connection to the update server right now." if result != HTTPRequest.RESULT_SUCCESS
				else "The update server is busy (%d). Try again in a bit." % code)
		return
	var found := UpdateFeed.find_update(JSON.parse_string(body.get_string_from_utf8()), current_version, plat)
	if found.is_empty():
		release = {}
		_set_state(State.UP_TO_DATE)
		return
	var same: bool = not release.is_empty() and release.tag == found.tag
	release = found
	if same and _before_check in [State.READY, State.NEEDS_PERMISSION, State.INSTALLING]:
		_set_state(_before_check)
	elif can_self_install() and FileAccess.file_exists(_file_path()):
		# Fetched on an earlier run but never installed: offer it ready to go.
		_verify(_file_path(), true)
	else:
		_set_state(State.AVAILABLE)


func _check_failed(msg: String) -> void:
	if not release.is_empty():
		_set_state(_before_check if _before_check != State.CHECKING else State.AVAILABLE)
	elif manual_check:
		_fail(msg)
	else:
		_set_state(State.IDLE)
		_next_check = 15.0 * 60.0


func _on_downloaded(result: int, code: int, _headers_in: PackedStringArray, _body: PackedByteArray) -> void:
	if state != State.DOWNLOADING:
		return
	var part := _dl.download_file
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		DirAccess.remove_absolute(part)
		match result:
			HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR, HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN:
				_fail("There isn't room to save the update. Free up %s and try again." % UpdateFeed.human_size(total))
			HTTPRequest.RESULT_SUCCESS:
				_fail("The download server said no (%d)." % code)
			_:
				_fail("The download was interrupted. Check your connection and try again.")
		return
	var path := _file_path()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(part, path)
	downloaded = total
	_verify(path)


func _verify(path: String, quiet := false) -> void:
	_quiet_verify = quiet
	_set_state(State.VERIFYING)
	_verify_result = ""
	_verify_task = WorkerThreadPool.add_task(func(): _verify_result = UpdateFeed.file_sha256(path), true, "Verify update")


func _on_verified() -> void:
	var path := _file_path()
	var want := str(release.asset.get("sha256", ""))
	var size_ok := int(release.asset.size) <= 0 or _file_size(path) == int(release.asset.size)
	if _verify_result == "" or not size_ok or (want != "" and want != _verify_result):
		DirAccess.remove_absolute(path)
		if _quiet_verify:
			_set_state(State.AVAILABLE)
		else:
			_fail("The download arrived damaged. Try again and it will fetch a fresh copy.")
		return
	_set_state(State.READY)


func _file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_length() if f else -1


func _apply_windows() -> void:
	_apply_result = UpdateFeed.swap_in_zip(_file_path(), OS.get_executable_path(), _apply_leftovers)


func _on_applied() -> void:
	if _apply_result != "":
		_fail(_apply_result)
		return
	var cfg := _settings()
	cfg.set_value("updater", "leftovers", _apply_leftovers)
	cfg.save(SETTINGS)
	DirAccess.remove_absolute(_file_path())
	var pid := OS.create_process(OS.get_executable_path(), OS.get_cmdline_args())
	if pid <= 0:
		_fail("Updated! Weed World couldn't reopen itself, so start it again to play the new version.")
		return
	get_tree().quit()


func _fail(msg: String) -> void:
	error_text = msg
	_set_state(State.FAILED)


func _settings() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	return cfg


## Remembers the version that ran last, so a fresh update can say hello.
func _note_version() -> void:
	var cfg := _settings()
	var last := str(cfg.get_value("updater", "last_version", ""))
	if last != "" and UpdateFeed.compare(current_version, last) > 0:
		updated.emit.call_deferred(last, current_version)
	cfg.set_value("updater", "last_version", current_version)
	cfg.save(SETTINGS)
	if not (cfg.get_value("updater", "leftovers", []) as Array).is_empty():
		_cleanup_tries = 12


func _cleanup_leftovers() -> void:
	var cfg := _settings()
	var left: Array = []
	for p in cfg.get_value("updater", "leftovers", []):
		if FileAccess.file_exists(p) and DirAccess.remove_absolute(p) != OK:
			left.append(p)
	cfg.set_value("updater", "leftovers", left)
	cfg.save(SETTINGS)
	if left.is_empty():
		_cleanup_tries = 0


## Drops downloads for versions this build already is (or is newer than).
func _tidy_downloads() -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		return
	for f in d.get_files():
		var m := RegEx.create_from_string("(\\d+\\.\\d+\\.\\d+)").search(f)
		if f.ends_with(".part") or m == null or UpdateFeed.compare(m.get_string(1), current_version) <= 0:
			d.remove(f)
