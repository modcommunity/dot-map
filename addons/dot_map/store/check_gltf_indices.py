#!/usr/bin/env python3
"""Fail if any glTF/GLB under the given folders has a primitive whose indices reach past its vertex count (the engine
errors per read and names no file). Usage: check_gltf_indices.py DIR... ; exit 1 and one line per bad model."""
import base64, json, os, struct, sys

CT = {5121: ("B", 1), 5123: ("H", 2), 5125: ("I", 4)}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def load(path):
    data = open(path, "rb").read()
    if path.endswith(".glb"):
        if data[:4] != b"glTF":
            raise ValueError("not a GLB")
        off, js, bins = 12, None, None
        while off < len(data):
            ln, kind = struct.unpack_from("<II", data, off)
            chunk = data[off + 8: off + 8 + ln]
            if kind == 0x4E4F534A:
                js = json.loads(chunk)
            elif kind == 0x004E4942 and bins is None:
                bins = chunk
            off += 8 + ln
        return js, [bins]
    js = json.loads(data)
    bufs = []
    for b in js.get("buffers", []):
        uri = b.get("uri", "")
        if uri.startswith("data:"):
            bufs.append(base64.b64decode(uri.split(",", 1)[1]))
        else:
            from urllib.parse import unquote
            with open(os.path.join(os.path.dirname(path), unquote(uri)), "rb") as f:
                bufs.append(f.read())
    return js, bufs


def check(path):
    js, bufs = load(path)
    acc, views = js.get("accessors", []), js.get("bufferViews", [])
    for mi, mesh in enumerate(js.get("meshes", [])):
        for pi, prim in enumerate(mesh.get("primitives", [])):
            if "indices" not in prim or "POSITION" not in prim.get("attributes", {}):
                continue
            ia, pa = acc[prim["indices"]], acc[prim["attributes"]["POSITION"]]
            fmt, size = CT[ia["componentType"]]
            view = views[ia["bufferView"]]
            buf = bufs[view.get("buffer", 0)]
            start = view.get("byteOffset", 0) + ia.get("byteOffset", 0)
            stride = view.get("byteStride", size)
            hi = 0
            for i in range(ia["count"]):
                hi = max(hi, struct.unpack_from("<" + fmt, buf, start + i * stride)[0])
            if hi >= pa["count"]:
                return "mesh %d primitive %d: index %d but only %d vertices" % (mi, pi, hi, pa["count"])
    return ""


def main(dirs):
    bad = 0
    n = 0
    for d in dirs:
        for root, _, files in os.walk(d):
            for f in sorted(files):
                if f.endswith((".gltf", ".glb")):
                    p = os.path.join(root, f)
                    n += 1
                    try:
                        why = check(p)
                    except Exception as e:
                        why = "unreadable: %s" % e
                    if why:
                        bad += 1
                        print("BAD %s: %s" % (p, why))
    print("%d models scanned, %d bad" % (n, bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:] or ["."]))
