# Add culling to your level in 5 minutes

For a level you built in the editor, not a converted BSP map (those use [visibility.md](visibility.md)). Nothing here is on by default and nothing needs a script in your game.

## What Godot already does, and what this adds

| Need | Godot 4.7 | dot-map |
| --- | --- | --- |
| Hide what is behind a wall | `OccluderInstance3D` with a `BoxOccluder3D`, `QuadOccluder3D`, `PolygonOccluder3D` or a baked scene occluder; turn on `Viewport.use_occlusion_culling` (Project Settings, Rendering, Occlusion Culling) | Nothing; use it |
| Hide what is far | `GeometryInstance3D.visibility_range_end` and fade; HLOD by pairing two ranges | Nothing; use it |
| Skip a node off-screen | `VisibleOnScreenNotifier3D` (frustum only, ignores walls) | Nothing |
| Rooms and portals | Removed. Godot 4.0 to 4.3 had `RoomManager`, `Room` and `Portal`; none exists in 4.7 (`ClassDB.class_exists("RoomManager")` is false) | No room graph either: occluders do the job for static walls, and a room node would only duplicate them |
| Bake occluders | `OccluderInstance3D` has its own bake, which merges all meshes into one simplified mesh: slow and fuzzy on a level full of props | `DotOccluderBaker`: only large flat faces, as quads, reproducible, headless |
| A door that opens | An occluder cannot change shape; you would toggle one by hand | `DotAreaPortal`: a doorway box that occludes while closed |

An honest summary: Godot does the culling. These two classes feed it the occluders a level author would otherwise place by hand, and keep a door's occluder in step with the door.

## 1. Bake occluders from the walls

In the editor, open your level scene (a `Node3D` root) and choose Project, Tools, **Bake occluders for the edited scene**; save. Or headless, for CI and scripts, from the dot-map checkout or with the script's path:

```bash
godot --headless --path . --import
godot --headless --path . -s tools/bake_occluders.gd -- res://levels/arena.tscn [--out=res://levels/arena_baked.tscn] [--dry]
```

It prints `N meshes, N large faces, N quads` and writes one `OccluderInstance3D` named `BakedOccluders` into the scene. Baking again replaces it.

What becomes a quad: a group of one mesh's triangles on one plane that is at least 6 m² (`min_area`), at least 1.5 m on its short side (`min_side`) and at least 85% filled (`min_fill`). A wall with a doorway cut into one mesh fails the fill test and is skipped, because a quad over the hole would hide the next room; build it as several boxes instead, or put a `DotAreaPortal` in the hole. Every quad is pulled in 4 cm from its edges so it never hides the face it lies on. At most 256 are kept, the largest first.

Never baked: hidden nodes, translucent meshes (`transparency`, or a material with alpha), shadow-only meshes, and anything in the group `dot_no_occluder`. Set the group on glass, foliage planes and anything that moves or can be destroyed.

Then turn on **Rendering, Occlusion Culling, Use Occlusion Culling** in Project Settings. In code, `DotOccluderBaker.new().bake(level_root)` returns a `DotResult` whose value is the node; set `min_area`, `min_side`, `min_fill`, `inset` and `max_quads` on the baker first.

## 2. Doors: DotAreaPortal

Add a `DotAreaPortal` in the doorway (Create Node, search "portal"), set `size` to the opening (the orange box is the editor gizmo; it turns green when open), and drive it from the door:

```gdscript
@onready var portal: DotAreaPortal = $Doorway
func _on_door_opened(opened: bool) -> void:
    portal.set_open(opened)   # or set portal.open; both emit toggled(open)
```

Closed, it blocks the view, so the room behind a shut door costs nothing. It starts closed; tick `open` for a doorway with no door. `is_blocking()` says what it is doing now. Do not make `size` larger than the opening.

On a converted BSP map, `DotMapVisibility.bind_area_portals(level_root)` makes every portal that has a `key` (the map's area portal) or a `door` (the door entity's target name) drive the map's own portals too.

## 3. Check it

`godot --headless --path . res://examples/culling_demo.tscn` (28 checks in 4 sections: the baker, the portal, the binding and a save round trip).

The occlusion scene is rebuilt in the background after a change, so the first frames after a bake or a door move still draw everything. A frame-time or draw-call test must wait about a second after changing an occluder before it counts.

## Measured

`examples/culling_demo.tscn`: eight 10 m rooms in a row, 30 props each, doorways on alternating sides, camera in the first room (`tools/shot_culling.sh --shot=<dir>` through `../gpu.sh shot`, GTX 1660 Ti, Forward+, 960×540, after a 2 s settle):

| | draw calls |
| --- | --- |
| No occluders | 283 |
| Baked occluders (80 quads) | 45 |
| Baked occluders and every portal closed | 34 |

The frame does not change: [before](img/culling_before.png) and [after](img/culling_after.png) are the same picture, which is the point. A straight line of sight through open doorways keeps drawing what it sees; closing the portals is what removes that.

## Limits

- Static geometry only: a quad does not follow a moved mesh. Rebake after moving walls, and keep movers out with `dot_no_occluder`.
- Planar groups are per mesh. Curved walls and subdivided floors produce few or no quads; add a `BoxOccluder3D` by hand there.
- Characters and particles are hidden by the same occluders; anything that must show through walls on purpose sets `ignore_occlusion_culling` on its node.
