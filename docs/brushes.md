# Brushes

`DotMapBrush` (`addons/dot_map/brushes/`) is the family's one set of map-building solids: box, wedge (alias ramp), stairs, cylinder, cone, spike, arch, quarter_pipe and slab_holes. A brush is a dictionary (`{"kind": "stairs", "size": [4, 3, 6], "params": {"steps": 6}, "uv_metres": 1.0}`), so a map document can carry one and a generator can write one; `DotMapBrush.build_body(spec, material)` returns a `StaticBody3D` with the mesh, one convex collision shape per piece and the material in the slot, and `validate(spec)` says what is wrong with a spec (`DotError.CODE_INVALID`).

**Why convex pieces and no trimesh.** An arch, a quarter-pipe and a slab with holes are concave. Each is cut into convex pieces (arch segments, slices under the curve, boxes round the holes), so the solver sees convex shapes and a character walks over the joins without catching. The mesh is the pieces' faces minus the faces two pieces share exactly, which would sit inside the solid.

**Why UVs in metres.** Each face is laid out on its own plane, one UV unit per `uv_metres`, so a brush twice as long shows twice the texture and a slope's texture is the size of a wall's. A brush scaled with a node transform is stretched like any mesh: change `size`, not the scale. `DotMapSurfaces` materials are triplanar and ignore UVs, so both routes tile at world scale; the UVs are for a plain tiling material and for normal maps.

**Direction.** Wedge, stairs and quarter-pipe climb toward +x; turn the node. Brushes are centred on their bounding box, like a map box.

`examples/brushes_demo.tscn` is the suite (62 checks: bounds, centring, convex collision, UV spans, a slope's UV length, rays down stairs, through an arch's opening and a slab's holes). With `-- --shot=<prefix>` it renders three frames on a checker, which is how a stretched slope or an inside-out face shows; run it under `xvfb-run`, not `--headless`.

Not here: a map editor, boolean cuts, curved normals (faces are flat, the cylinder is 16-sided by default; raise `segments`), and per-face materials.
