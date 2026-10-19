# Surfaces: a material per kind of surface

`DotMapSurfaces` (`addons/dot_map/surfaces/`) turns a surface kind into a `StandardMaterial3D`, so a map generator names what a thing is made of and never what colour it is.

```gdscript
var surfaces := DotMapSurfaces.new()                  # textures from this addon's folder
wall.material_override = surfaces.material(&"brick")
floor.material_override = surfaces.material(&"tile_dark", Color(0.8, 0.85, 0.9))   # a tint multiplies the photo
var res := surfaces.try_material(&"typo")            # DotResult: invalid for an unknown kind, io for a texture that did not load
```

## Kinds

`concrete`, `concrete_clean`, `plaster`, `brick`, `tile_white`, `tile_dark`, `tile_checker`, `wood_floor`, `wood_planks`, `asphalt`, `metal`, `rust`, `corrugated`, `grass`, `ground`. `DotMapSurfaces.ALIASES` maps the words a generator already uses (`wall`, `floor`, `road`, `roof`, `dirt`, `container`...) onto them; `resolve(name)` says which. `material()` always answers: an unknown kind or a missing texture draws flat grey and logs once, so one bad word in a map document costs a grey wall, not the map.

## Why it is shaped this way

- **World-space triplanar.** A code-built box has no authored UVs and a map is hundreds of boxes of every size; per-box UVs stretch a brick across a 2 m wall and a 20 m one alike. `KINDS[kind].meters` is how wide one texture is in the world, so the density is the same on every wall. It is a plain material flag, so Forward+ and the browser's Compatibility renderer draw it the same (rendered in both before commit).
- **Loaded by path, not referenced by a scene.** An imported texture a scene references is recorded at its authored location, and a delivered pack mounts elsewhere. The library calls `load()` on `root + "/<kind>/albedo.jpg"`; a game whose pack carries the textures sets `root` to the mounted folder or `path_fn` to its path rebasing function. **The default root is this addon's folder, which a pack does not carry** (a pack holds the game's tree; `res://addons/...` means the host build's copy), so a game that delivers its maps copies or links `surfaces/` into its own tree and passes that root.
- **Lightmaps bake from albedo.** The albedo is the unaltered photograph and the tint multiplies it, so what is baked is what is drawn. Triplanar has no UV for the baker to sample: check a baked map's brightness against the unbaked one before trusting it.
- **Imported lossy (WebP), not VRAM compressed**: the family has no VRAM-compressed textures yet (mobile browsers need ETC2/ASTC and the export would have to ship both), and lossy keeps the download small. The `.import` files are committed with mipmaps on and `detect_3d/compress_to=0`.

## Size

A pack ships the imported form only (the source JPG stays behind, [publishing.md](../../dot-cloud/docs/publishing.md#the-source-of-an-imported-asset-stays-behind)), so the right column is what a map costs to download; a map using six kinds is about 2-3 MB.

| Kind | Source JPG | Imported (ships) |
| --- | --- | --- |
| asphalt | 1.10 MB | 0.75 MB |
| brick | 1.05 MB | 0.73 MB |
| concrete | 0.92 MB | 0.59 MB |
| concrete_clean | 0.50 MB | 0.21 MB |
| corrugated | 0.62 MB | 0.23 MB |
| grass | 1.63 MB | 1.27 MB |
| ground | 1.78 MB | 1.23 MB |
| metal | 0.52 MB | 0.32 MB |
| plaster | 0.79 MB | 0.41 MB |
| rust | 0.63 MB | 0.28 MB |
| tile_checker | 0.34 MB | 0.16 MB |
| tile_dark | 0.54 MB | 0.28 MB |
| tile_white | 0.25 MB | 0.08 MB |
| wood_floor | 0.51 MB | 0.21 MB |
| wood_planks | 0.63 MB | 0.34 MB |
| **total** | 11.81 MB | 7.08 MB |

Credits and licences (all ambientCG, CC0): `addons/dot_map/surfaces/CREDITS.md`.

## Not here

No decals, no blood or graffiti, no rubble models: CC0 sources for those were not found (ambientCG's decal category is stains, road markings and manhole covers; Poly Haven has barriers, barrels, tyres and a chain-link fence, but no pallets or rubble).
