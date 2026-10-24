class_name UpdateFeed
extends RefCounted
## The pure logic behind in-game updates, kept free of nodes so the headless
## check can drive it: reading the GitHub releases feed, comparing versions,
## picking this platform's download, gathering every patch note the player
## has missed, checking a download's SHA-256, and swapping a new Windows
## build in next to the running one.

const REPO := "jpcpais01/weed-world"
const FEED_URL := "https://api.github.com/repos/%s/releases?per_page=20" % REPO
const RELEASES_URL := "https://github.com/%s/releases/latest" % REPO
## How many hour groups of patch notes the update card shows at most.
const MAX_NOTE_GROUPS := 6


## "v0.1.24" or "0.1.24" -> [0, 1, 24]. Anything that is not a number counts
## as 0, so a malformed tag never looks newer than a real one.
static func parse_version(s: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	s = s.strip_edges().trim_prefix("v").trim_prefix("V")
	for part in s.split("."):
		out.append(part.to_int() if part.is_valid_int() else 0)
	return out


## -1 if a is older than b, 0 if equal, 1 if newer. Missing parts count as 0.
static func compare(a: String, b: String) -> int:
	var va := parse_version(a)
	var vb := parse_version(b)
	for i in maxi(va.size(), vb.size()):
		var x := va[i] if i < va.size() else 0
		var y := vb[i] if i < vb.size() else 0
		if x != y:
			return 1 if x > y else -1
	return 0


## "android", "windows" or "other" for the build that is running.
static func platform() -> String:
	if OS.has_feature("android"):
		return "android"
	if OS.has_feature("windows"):
		return "windows"
	return "other"


## The release asset this platform installs, or {} if there is none.
static func pick_asset(release: Dictionary, plat: String) -> Dictionary:
	for a in release.get("assets", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var asset_name := str(a.get("name", ""))
		var hit := false
		match plat:
			"android":
				hit = asset_name.ends_with(".apk")
			"windows":
				hit = asset_name.ends_with("-windows.zip")
		if hit:
			var digest := str(a.get("digest", ""))
			return {
				"name": asset_name,
				"url": str(a.get("browser_download_url", "")),
				"size": int(a.get("size", 0)),
				"sha256": digest.trim_prefix("sha256:").to_lower() if digest.begins_with("sha256:") else "",
			}
	return {}


## Reads the releases feed (a JSON array, newest first or not) and returns the
## newest published release that is newer than `current`, as
## {version, tag, page, asset, notes, published}, or {} when there is none.
## `asset` is {} on a platform without its own download (the card then offers
## the download page). `notes` gathers the patch notes of every release the
## player has missed.
static func find_update(feed: Variant, current: String, plat: String) -> Dictionary:
	if typeof(feed) != TYPE_ARRAY:
		return {}
	var newer: Array[Dictionary] = []
	for r in feed:
		if typeof(r) != TYPE_DICTIONARY or r.get("draft", false) or r.get("prerelease", false):
			continue
		var tag := str(r.get("tag_name", ""))
		if tag.is_empty() or compare(tag, current) <= 0:
			continue
		newer.append(r)
	if newer.is_empty():
		return {}
	newer.sort_custom(func(a, b): return compare(str(a.tag_name), str(b.tag_name)) > 0)
	# The newest release that actually carries this platform's file wins; a
	# release still uploading its assets is skipped until it is complete.
	var best: Dictionary = {}
	for r in newer:
		if plat == "other" or not pick_asset(r, plat).is_empty():
			best = r
			break
	if best.is_empty():
		return {}
	var tag := str(best.tag_name)
	return {
		"version": tag.trim_prefix("v"),
		"tag": tag,
		"page": str(best.get("html_url", RELEASES_URL)),
		"asset": pick_asset(best, plat),
		"notes": merge_notes(newer.filter(func(r): return compare(str(r.tag_name), tag) <= 0)),
		"published": str(best.get("published_at", "")),
	}


## Release bodies hold the newest hour group of PATCH_NOTES.md, so releases
## merged in the same hour repeat a heading. Keeps each heading once (from the
## newest release, which has the fullest list), newest first, and drops the
## download footer the release page adds.
static func merge_notes(releases: Array) -> String:
	var seen := {}
	var groups: Array[String] = []
	var more := false
	for r in releases:
		var heading := ""
		var lines := PackedStringArray()
		for raw in str(r.get("body", "")).replace("\r", "").split("\n"):
			var line := raw.strip_edges(false, true)
			if line.begins_with("**Downloads:**"):
				continue
			if line.begins_with("## "):
				if heading != "" and not seen.has(heading):
					seen[heading] = true
					groups.append("\n".join(lines).strip_edges())
				heading = line
				lines = PackedStringArray([line])
			elif heading != "":
				lines.append(line)
		if heading != "" and not seen.has(heading):
			seen[heading] = true
			groups.append("\n".join(lines).strip_edges())
	if groups.size() > MAX_NOTE_GROUPS:
		groups.resize(MAX_NOTE_GROUPS)
		more = true
	var md := "\n\n".join(groups)
	if more:
		md += "\n\n…and even more, all listed on the download page."
	return md


## Lowercase hex SHA-256 of a file, or "" if it can't be read. Reads in 1 MB
## chunks, so call it off the main thread for big files.
static func file_sha256(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var left := f.get_length()
	while left > 0:
		var chunk := f.get_buffer(mini(left, 1 << 20))
		if chunk.is_empty():
			return ""
		ctx.update(chunk)
		left -= chunk.size()
	return ctx.finish().hex_encode()


## Installs a Windows release zip next to the running game. Every file is
## first written beside its target as "<name>.new", then the old file is
## renamed to "<name>.old" (Windows lets a running .exe be renamed, just not
## overwritten) and the new one takes its place. The zip's .exe always lands
## on `exe_path`, even if the player renamed the game. Rolls everything back
## if any step fails. Returns "" on success or a short reason, and fills
## `leftovers` with the .old files to delete once the old game has exited.
static func swap_in_zip(zip_path: String, exe_path: String, leftovers: Array) -> String:
	var zip := ZIPReader.new()
	if zip.open(zip_path) != OK:
		return "The download couldn't be opened."
	var dir := exe_path.get_base_dir()
	var staged: Array = []   # [target, temp]
	var found_exe := false
	var err := ""
	for entry in zip.get_files():
		if entry.ends_with("/") or entry.contains(".."):
			continue
		var target := dir.path_join(entry)
		var is_exe := entry.get_base_dir() == "" and entry.get_extension().to_lower() == "exe"
		if is_exe:
			if found_exe:
				continue
			found_exe = true
			target = exe_path
		var data := zip.read_file(entry)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var tmp := target + ".new"
		var f := FileAccess.open(tmp, FileAccess.WRITE)
		if f == null:
			err = "The game folder can't be written to. Try moving Weed World somewhere like Documents."
			break
		f.store_buffer(data)
		f.close()
		if FileAccess.get_file_as_bytes(tmp).size() != data.size():
			err = "Writing the new files failed. Is the disk full?"
			break
		# The .exe goes last, so a failure never leaves a new game with old data.
		if is_exe:
			staged.append([target, tmp])
		else:
			staged.push_front([target, tmp])
	zip.close()
	if err == "" and not found_exe:
		err = "The download didn't contain the game."
	if err != "":
		for s in staged:
			DirAccess.remove_absolute(s[1])
		return err

	var done: Array = []   # [target, old or ""]
	for s in staged:
		var target: String = s[0]
		var tmp: String = s[1]
		var old := ""
		if FileAccess.file_exists(target):
			old = target + ".old"
			if FileAccess.file_exists(old):
				DirAccess.remove_absolute(old)
			if DirAccess.rename_absolute(target, old) != OK:
				err = "Couldn't move the old %s aside." % target.get_file()
				break
		if DirAccess.rename_absolute(tmp, target) != OK:
			if old != "":
				DirAccess.rename_absolute(old, target)
			err = "Couldn't put the new %s in place." % target.get_file()
			break
		done.append([target, old])
	if err != "":
		for s in staged:
			if FileAccess.file_exists(s[1]):
				DirAccess.remove_absolute(s[1])
		done.reverse()
		for d in done:
			if d[1] != "":
				DirAccess.remove_absolute(d[0])
				DirAccess.rename_absolute(d[1], d[0])
		return err
	for d in done:
		if d[1] != "":
			leftovers.append(d[1])
	return ""


static func human_size(bytes: int) -> String:
	if bytes >= 1 << 30:
		return "%.1f GB" % (bytes / 1073741824.0)
	if bytes >= 1 << 20:
		return "%.1f MB" % (bytes / 1048576.0)
	if bytes >= 1 << 10:
		return "%d KB" % (bytes >> 10)
	return "%d B" % bytes


static func human_eta(seconds: float) -> String:
	if seconds < 0.0 or is_inf(seconds) or is_nan(seconds):
		return ""
	if seconds < 10.0:
		return "a few seconds left"
	if seconds < 60.0:
		return "about %d s left" % (int(ceil(seconds / 5.0)) * 5)
	if seconds < 3600.0:
		var m := int(round(seconds / 60.0))
		return "about %d min left" % m
	return "over an hour left"
