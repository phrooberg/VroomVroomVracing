# Map generation

Builds a 3D city from a PNG at runtime, then turns it into a race.

| File | What it does |
|---|---|
| `map_generator.gd` (`MapGenerator`) | PNG to 3D map. Black pixels become box buildings, every other colour becomes road. Also makes random city PNGs. |
| `race_generator.gd` (`RaceGenerator`) | Picks a circuit or point-to-point route along the road tiles, with start, finish and checkpoints. |
| `map_demo.tscn` / `map_demo.gd` | Demo scene with a simple camera. Open it and press **F6**. |

## Map rules

- One pixel = one tile (`tile_size`, 4 m by default).
- Black (or very dark, or transparent) = building. Neighbouring black pixels are merged into boxes of up to `max_building_tiles` x `max_building_tiles` with random heights.
- Anything else = road. Lane colours from `destmap_traffic.gd` are shown as a light tint (`show_lane_colors`).
- The top of the image is north, which is **-Z** in Godot. Blue (northbound) lanes point to -Z, yellow to +Z, red (east) to +X, green (west) to -X. A blue "N" floats past the north edge.
- Grid cell `(x, y)` is the same as pixel `(x, y)`, so the destination-map scripts and the 3D map share coordinates. Use `grid_to_world()` and `world_to_grid()` to convert.

## Demo controls

| Key | Action |
|---|---|
| 1 / 2 / 3 | Load `grid.png` / `grid_traffic_lanes.png` / `grid_traffic_lanes_2.png` |
| G | Generate a new random city (with traffic lane colours) |
| C / P | New circuit / new point-to-point race |
| M | Save the current map PNG to `user://` (path is printed in the Output panel) |
| WASD or arrows, Q / E, mouse wheel | Move, rotate, zoom the camera |
| Drag a PNG onto the game window | Build a map from it |

## Using it from code

```gdscript
var map := MapGenerator.new()
add_child(map)
map.generate_from_file("res://grid.png")              # or generate_from_texture / generate_from_image
# map.generate_from_image(MapGenerator.make_random_city_image(48, 48))

var race := RaceGenerator.new()
race.map = map
race.race_type = RaceGenerator.RaceType.CIRCUIT        # or POINT_TO_POINT
add_child(race)                                        # builds a race now and after every new map

car.global_transform = race.get_start_transform()
race.checkpoint_passed.connect(func(i, body): print(body.name, " passed checkpoint ", i))
var goal: Vector2i = race.get_finish_cell()            # destination for a destination-map
```

Useful data after generation: `map.road` (1 = road, index `y * width + x`), `map.source_image`, `race.route` (grid cells in driving order), `race.route_world` (3D points), `race.checkpoint_indices` (last one is the finish line).

Routes use `AStarGrid2D`. Tiles already on the route get more expensive, so later legs pick other streets; the generator makes `attempts` tries and keeps the one that overlaps itself least.
