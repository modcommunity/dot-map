class_name DotMapVpkWriter
extends RefCounted

## Writes tiny VPK archives and VTF files of made-up pixels: the fixtures for [DotMapVpk] and [DotMapVtf], for a game's
## own tests of what it builds on them, and for a tool that needs a stand-in install. It never holds or writes anything
## of Valve's: the bytes are the caller's.


## A VPK at [param base]`_dir.vpk` (and `_000.vpk`) holding [param files]: path -> [bytes, part (-1 stored in the dir,
## else 0), bytes preloaded in the tree]. [param version] is 1 or 2. Each CRC is off by one when [param bad_crc]. The
## `_000.vpk` is left out when [param skip_part] (a dedicated server's install). Returns [constant OK] or the error.
static func write_vpk(base: String, files: Dictionary, version := 2, bad_crc := false, skip_part := false) -> Error:
	var by_ext := {}
	for path: String in files:
		var folders: Dictionary = by_ext.get_or_add(path.get_extension(), {})
		(folders.get_or_add(path.get_base_dir(), []) as Array).append(path)
	var tree := PackedByteArray()
	var in_dir := PackedByteArray()
	var part := PackedByteArray()
	for ext: String in by_ext:
		tree.append_array(_cstr(ext))
		for folder: String in by_ext[ext]:
			tree.append_array(_cstr(folder))
			for path: String in by_ext[ext][folder]:
				var bytes: PackedByteArray = files[path][0]
				var preloaded: int = files[path][2]
				var body := bytes.slice(preloaded)
				var stored_in_dir := int(files[path][1]) < 0
				var e := PackedByteArray()
				e.resize(18)
				e.encode_u32(0, DotMapVpk.crc32(bytes) ^ (1 if bad_crc else 0))
				e.encode_u16(4, preloaded)
				e.encode_u16(6, DotMapVpk.IN_DIR if stored_in_dir else 0)
				e.encode_u32(8, (in_dir if stored_in_dir else part).size())
				e.encode_u32(12, body.size())
				e.encode_u16(16, 0xFFFF)
				tree.append_array(_cstr(path.get_file().get_basename()))
				tree.append_array(e)
				tree.append_array(bytes.slice(0, preloaded))
				(in_dir if stored_in_dir else part).append_array(body)
			tree.append(0)
		tree.append(0)
	tree.append(0)
	var head := PackedByteArray()
	head.resize(12 if version == 1 else 28)
	head.encode_u32(0, DotMapVpk.SIG)
	head.encode_u32(4, version)
	head.encode_u32(8, tree.size())
	if version == 2:
		head.encode_u32(12, in_dir.size())
	var made := DirAccess.make_dir_recursive_absolute(base.get_base_dir())
	if made != OK:
		return made
	var f := FileAccess.open(base + "_dir.vpk", FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(head + tree + in_dir)
	f.close()
	if skip_part:
		return OK
	f = FileAccess.open(base + "_000.vpk", FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(part)
	f.close()
	return OK


## A VTF 7.2 header (80 bytes, no thumbnail) for a [param w] x [param h] image of [param mips] in VTF [param format].
static func vtf_head(w: int, h: int, format: int, mips: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(80)
	out.encode_u32(0, 0x00465456)  # "VTF\0"
	out.encode_u32(4, 7)
	out.encode_u32(8, 2)
	out.encode_u32(12, 80)
	out.encode_u16(16, w)
	out.encode_u16(18, h)
	out.encode_u16(24, 1)
	out.encode_float(48, 1.0)
	out.encode_s32(52, format)
	out[56] = mips
	out.encode_s32(57, -1)
	out.encode_u16(63, 1)
	return out


## An RGBA8888 VTF: its largest mip [param top], the smaller ones [param rest] (stored smallest first).
static func vtf_rgba(w: int, h: int, mips: int, top: Color, rest: Color) -> PackedByteArray:
	var out := vtf_head(w, h, 0, mips)
	for m in range(mips - 1, -1, -1):
		var c := top if m == 0 else rest
		for _i in maxi(1, w >> m) * maxi(1, h >> m):
			out.append_array(PackedByteArray([c.r8, c.g8, c.b8, c.a8]))
	return out


## A one-mip VTF of [param format] (a 4-byte-per-pixel one such as 12 BGRA8888, or 3 BGR888 at 3 bytes) whose every
## pixel is the [param pixel] bytes as stored.
static func vtf_flat(w: int, h: int, format: int, pixel: PackedByteArray) -> PackedByteArray:
	var out := vtf_head(w, h, format, 1)
	for _i in w * h:
		out.append_array(pixel)
	return out


## A one-mip DXT1 VTF, every block colour0 [param rgb565].
static func vtf_dxt1(w: int, h: int, rgb565: int) -> PackedByteArray:
	var out := vtf_head(w, h, 13, 1)
	for _b in (w / 4) * (h / 4):
		var block := PackedByteArray()
		block.resize(8)
		block.encode_u16(0, rgb565)
		out.append_array(block)
	return out


static func _cstr(s: String) -> PackedByteArray:
	var out := s.to_utf8_buffer()
	out.append(0)
	return out
