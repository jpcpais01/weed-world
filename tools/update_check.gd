extends SceneTree
## Headless check of the in-game updater's logic: version comparison, picking
## the right release and download from a GitHub feed, gathering missed patch
## notes, the SHA-256 check, the Windows swap-in (with the .exe renamed by the
## player) and every state of the update card. Exits non-zero on failure.
##   godot --headless --path . -s res://tools/update_check.gd

const UpdaterScript := preload("res://autoload/updater.gd")
const S := UpdaterScript.State

var _ok := true
var _frames := 0
var _u: Node
var _prompt: CanvasLayer


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		print("update_check: FAIL ", what)


func _initialize() -> void:
	_versions()
	_feed()
	_hash()
	_swap()
	_card()


func _versions() -> void:
	_check(UpdateFeed.compare("v0.1.20", "0.1.19") == 1, "0.1.20 > 0.1.19")
	_check(UpdateFeed.compare("0.1.9", "0.1.10") == -1, "numeric, not text, order")
	_check(UpdateFeed.compare("v0.2", "0.2.0") == 0, "missing parts count as 0")
	_check(UpdateFeed.compare("garbage", "0.0.1") == -1, "junk tags never look newer")


func _release(tag: String, body: String, assets := true, draft := false) -> Dictionary:
	var v := tag.trim_prefix("v")
	var r := {"tag_name": tag, "draft": draft, "prerelease": false, "body": body,
			"html_url": "https://github.com/x/releases/tag/" + tag, "published_at": "2026-10-24T12:00:00Z", "assets": []}
	if assets:
		r.assets = [
			{"name": "WeedWorld-%s-windows.zip" % v, "size": 1000, "digest": "sha256:ABC",
					"browser_download_url": "https://example.com/%s.zip" % v},
			{"name": "WeedWorld-%s.apk" % v, "size": 2000, "digest": "sha256:def",
					"browser_download_url": "https://example.com/%s.apk" % v},
		]
	return r


func _feed() -> void:
	var foot := "\n\n**Downloads:** `WeedWorld.apk` for Android."
	var feed := [
		_release("v0.1.23", "## 24 Oct 2026 · 14:00 UTC\n- **Still uploading.**" + foot, false),
		_release("v0.1.22", "## 24 Oct 2026 · 13:00 UTC\n- **Updates.** In game.\n- **Two.** More." + foot),
		_release("v0.1.24", "## 24 Oct 2026 · 15:00 UTC\n- **Draft.**", true, true),
		_release("v0.1.21", "## 24 Oct 2026 · 13:00 UTC\n- **Updates.** In game." + foot),
		_release("v0.1.20", "## 24 Oct 2026 · 12:00 UTC\n- **Stumps.** Solid." + foot),
		_release("v0.1.19", "## 24 Oct 2026 · 11:00 UTC\n- **Old.** Already have it." + foot),
	]
	var up := UpdateFeed.find_update(feed, "0.1.19", "android")
	_check(up.get("version") == "0.1.22", "newest complete release offered (got %s)" % up.get("version"))
	_check(up.get("asset", {}).get("name") == "WeedWorld-0.1.22.apk", "Android gets the APK")
	_check(up.get("asset", {}).get("sha256") == "def", "digest parsed")
	var notes: String = up.get("notes", "")
	_check(notes.count("13:00 UTC") == 1, "same-hour groups merged once")
	_check(notes.contains("**Two.**"), "the fuller same-hour list wins")
	_check(notes.contains("12:00 UTC") and not notes.contains("11:00 UTC"), "notes cover exactly the missed releases")
	_check(not notes.contains("Downloads"), "download footer dropped")
	_check(notes.find("13:00") < notes.find("12:00"), "newest notes first")
	var win := UpdateFeed.find_update(feed, "0.1.19", "windows")
	_check(win.get("asset", {}).get("name") == "WeedWorld-0.1.22-windows.zip" and win.asset.sha256 == "abc", "Windows gets the zip")
	var other := UpdateFeed.find_update(feed, "0.1.19", "other")
	_check(other.get("version") == "0.1.23" and other.get("asset", {}).is_empty(), "other platforms get the page")
	_check(UpdateFeed.find_update(feed, "0.1.22", "android").is_empty(), "up to date offers nothing")
	_check(UpdateFeed.find_update(feed, "0.1.40", "android").is_empty(), "a newer local build offers nothing")
	_check(UpdateFeed.find_update({"message": "rate limited"}, "0.1.1", "android").is_empty(), "error payloads ignored")
	_check(UpdateFeed.human_eta(42.0) == "about 45 s left", "eta text")
	_check(UpdateFeed.human_size(68 << 20) == "68.0 MB", "size text")


func _hash() -> void:
	var p := "user://update_check_hash.bin"
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string("weed world")
	f.close()
	_check(UpdateFeed.file_sha256(p) == "e96682d9268a78f07e2e5767932cf2c275522dc7fe9d4c45af16d176e7f3c66f", "sha256")
	DirAccess.remove_absolute(p)


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _swap() -> void:
	var dir := ProjectSettings.globalize_path("user://update_check_swap")
	DirAccess.make_dir_recursive_absolute(dir)
	for n in ["MyGame.exe", "README.md", "MyGame.exe.old", "README.md.old", "extra/data.txt", "extra/data.txt.old"]:
		DirAccess.remove_absolute(dir.path_join(n))
	_write(dir.path_join("MyGame.exe"), "old game")
	_write(dir.path_join("README.md"), "old readme")
	var zip_path := dir.path_join("update.zip")
	var zp := ZIPPacker.new()
	zp.open(zip_path)
	for e in [["WeedWorld.exe", "new game"], ["README.md", "new readme"], ["extra/data.txt", "data"]]:
		zp.start_file(e[0])
		zp.write_file(e[1].to_utf8_buffer())
		zp.close_file()
	zp.close()
	var leftovers: Array = []
	var err := UpdateFeed.swap_in_zip(zip_path, dir.path_join("MyGame.exe"), leftovers)
	_check(err == "", "swap succeeds (%s)" % err)
	_check(FileAccess.get_file_as_string(dir.path_join("MyGame.exe")) == "new game", "exe swapped onto the running name")
	_check(FileAccess.get_file_as_string(dir.path_join("README.md")) == "new readme", "other files replaced")
	_check(FileAccess.get_file_as_string(dir.path_join("extra/data.txt")) == "data", "folders created")
	_check(FileAccess.get_file_as_string(dir.path_join("MyGame.exe.old")) == "old game", "old exe kept aside")
	_check(leftovers.size() == 2, "both replaced files queued for cleanup (%s)" % [leftovers])
	_check(not FileAccess.file_exists(dir.path_join("WeedWorld.exe")), "no stray exe")
	var bad := UpdateFeed.swap_in_zip(dir.path_join("missing.zip"), dir.path_join("MyGame.exe"), [])
	_check(bad != "", "a missing zip fails cleanly")


func _card() -> void:
	_u = UpdaterScript.new()
	_u.name = "Updater"
	root.add_child(_u)
	_u.current_version = "0.1.19"
	_u.plat = "android"
	_u.release = {"version": "0.1.22", "tag": "v0.1.22", "page": "https://example.com",
			"asset": {"name": "WeedWorld-0.1.22.apk", "url": "https://example.com/a.apk", "size": 70 << 20, "sha256": ""},
			"notes": "## 24 Oct 2026 · 13:00 UTC\n- **Updates [in game].** Tap to install.", "published": ""}
	_prompt = load("res://ui/update/update_prompt.gd").new(_u)
	root.add_child(_prompt)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		# Walk the card through every state on both platforms.
		for p in ["android", "windows", "other"]:
			_u.plat = p
			for s in S.values():
				_u.downloaded = 30 << 20
				_u.total = 70 << 20
				_u.speed = 2 << 20
				_u.error_text = "Something broke."
				_u._set_state(s)
				_prompt._open_panel()
				_prompt._process(0.1)
				_check(_prompt._title.text != "", "%s state %d has a title" % [p, s])
				if s == S.DOWNLOADING:
					_check(_prompt._status.text.contains("30.0 MB of 70.0 MB"), "download progress text (%s)" % _prompt._status.text)
				_prompt._close_panel()
		_u.plat = "android"
		_u._set_state(S.AVAILABLE)
		_prompt._open_panel()
		_check(_prompt._primary.text == "Update now", "Android offers an in-game update")
		_check(_prompt._notes.text.contains("[lb]in game]"), "release notes can't inject BBCode")
		_u.plat = "other"
		_prompt._sync()
		_check(_prompt._primary.text == "Open download page", "other platforms go to the download page")
	if _frames >= 4:
		print("update_check: ", "PASS" if _ok else "FAIL")
		quit(0 if _ok else 1)
	return false
