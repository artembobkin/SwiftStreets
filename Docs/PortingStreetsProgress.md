# Porting osm2streets: the record

How the port was made and checked, carried from the package where it was written (ImmersiveMapEditor, phases 9 and 10 of its porting plan, up to its commit `1d27d0f`).

## State

- The foundations: done. `Earcut`, `GeoAlgorithms`, `StreetGeom`, `OSMReader`, `CountryBoundaries` with the driving side, each with its tests.
- `Streets`: done. Muv's lane reading is ported as `MuvLanes` (MPL-2.0), and osm2lanes reads every lane through it. With no help from the Rust, the four outputs are byte-identical to the Rust on all 29 XML cases of osm2streets, on the Moscow region and on the five tiles (the parity table below), and `toGeoJSON` equals the committed `geometry.json` of all 29 cases.

## MuvLanes

`Sources/MuvLanes/`, the parts of muv-osm (rev `2404d40`) that `lanes()` reaches, every file under the MPL-2.0 with its notice:

- `Tags/`: `Tag` (the tag tree) and `DoubleTag`, `Parse` (the derived `FromOsmStr`: whole-string, ASCII-case-insensitive names, and serde's variant names).
- `Support/`: `RustStr` (Rust's `split`, `trim`, integer and `f32` parsing), `HashOrder` (see below).
- `Modes/`: `TMode` with its hierarchy and the reading of modes from subtags, `TModes`, `AccessLevel`, `Lifecycle`.
- `Units/`: `Number` (an `f32` with its significant figures, written as `Display` writes it), `Quantity`, the units the lanes use.
- `Conditional/`: `Conditional`, `Restriction`, `Condition`, `Compare`, `Operator`, `DateTimeRange`, and `OpeningHoursSyntax`, the recogniser of opening-hours-syntax 1.1.3's grammar and builder errors, which decides whether a condition is a date range.
- `Lanes/`: `Lanes`, `Lane`, travel lanes and `Turn`, the direction parsers (`AllParser`, `IndividualParser`), parking, railways, waterways, aeroways, `lanes()`.
- `Highway/`: `highway_lanes`, `BaseLanes`, side lanes, one-way, `parse_direction`, the classes and their access, the driving side, and the legal speeds (`SpeedDefault` over `SpeedDefaultTable.swift`, generated from `speed_default.rs`: 554 functions, 12 classes, decoded once).
- `Serde/MuvJSON`: what `serde_json::to_value` makes of a `Lane`, the `muv` property of the lane polygons.

Decisions:

- **The order of tag maps.** A `Tag`'s subtags are a Rust `HashMap` with rustc-hash's `FxBuildHasher`, and Muv iterates them where two keys mean the same thing (`Bus` and `bus`, `tricycle` and `auto_rickshaw`, a `bus:lanes` and an `hgv:lanes` of other lane counts: the first read splits the lanes and the other is ignored, two lifecycle prefixes). `HashOrder` reproduces it: rustc-hash 2.1's `FxHasher` over a `str` and hashbrown's bucket layout (8-byte control groups on aarch64, triangular probing, growth), iterated in bucket order. rustc-hash, hashbrown and opening-hours-syntax are MIT or Apache-2.0: their translations sit inside two MPL files, their MIT notices in the folder's `LICENSE`.
- **Release arithmetic.** The Rust oracle is a release build, where `u8` overflows wrap: the port wraps there too (`&+`, `&*`).
- **Conditions are not evaluated.** osm2lanes evaluates them only for a `date_time`, which the binary's configuration (and the Swift `MapConfig`) never has. `DateTimeRange` keeps the text and only checks that the opening-hours crate would parse it.
- **Equality.** `LaneSpec` holds the Muv `Lane` itself, compared with Muv's `PartialEq` (`Number` by value and figures, `Quantity` through conversion), as the Rust compares lanes in `CollapseDegenerateIntersections`.
- **The seam stays** (`LaneSpecSource`, default `MuvLaneSpecs`): the transformation tests run on made-up lanes.
- Muv's own bugs are kept: `SlightLeft`'s OSM name is `sharp_left`, the legacy parking condition reads its modes from the parking tags, `maxdraught` of a whole direction goes into `maxheight`, `carriageway_width` reads the root key `carriageway`, RGB colours are written without padding.

## Parity numbers

`swift test -c release -Xswiftc -enable-testing`, the Rust being `osm2streets-cli` (rev fc119c4, arm64, see `Docs/PortingParity.md`), with inferred sidewalks and kerbs. The port reads every lane itself. "Identical" means byte-identical GeoJSON text. 2026-10-25:

| Case | Roads | Intersections | Tag sets | plain | lanes | lane_markings | intersection_markings |
|---|---|---|---|---|---|---|---|
| osm2streets's 29 XML cases (all but the PBF `frederiksted`) | 4 to 515 | 4 to 409 | 2 to 180 | 29 identical | 29 identical | 29 identical | 29 identical |
| Moscow 2x2 region, with its clip | 4874 | 4642 | 943 | identical (9516 features) | identical (7557) | identical (58360) | identical (229) |
| Moscow tile 15/19808/10242, unclipped | 1563 | 1577 | 437 | identical (3140) | identical (2543) | identical (21213) | identical (65) |
| Moscow tile 15/19809/10242 | 1389 | 1377 | 284 | identical (2766) | identical (2479) | one of the 6 results of the Rust's orders (18026) | identical (59) |
| Moscow tile 15/19808/10243 | 2091 | 1846 | 383 | identical (3937) | identical (2699) | one of the 2 results of the Rust's orders (29442) | identical (59) |
| Moscow tile 15/19809/10243 | 1614 | 1529 | 370 | identical (3143) | identical (2746) | identical (22910) | identical (131) |
| Moscow tile 15/19810/10243 | 1394 | 1349 | 248 | identical (2743) | identical (2568) | identical (18110) | identical (71) |

The committed `geometry.json` of the 29 cases, made as osm2streets's tests make it (`MapConfig::default()`, invariants checked): 29 of 29 identical (8 to 1025 features).

MuvLanes against the Rust on synthetic ways (`Tests/StreetsTests/MuvLanes/`): one way per tag set across a box, in ten countries (RU, DE, GB, US, FR, NL, IE, AU, AT, BE), the four outputs compared:

- 280 tag sets written by hand (every class, lane counts and placements, per-lane keys, access with case and alias clashes, every kind of speed and condition, opening hours accepted and refused, sidewalks, cycleways, bus lanes and bays, shoulders, both parking schemes, widths and units, surfaces and colours, overtaking, railways, odd values): 10 of 10 boxes identical, 1537 to 1539 lanes each.
- 400 tag sets drawn at random per box (a highway class and 2 to 9 of 120 lane keys, SplitMix64 from the box's name): 10 of 10 identical, 1941 to 2189 lanes each. One random way in FR makes the Rust itself panic (geom's `dist_along` of a negative distance, `polyline.rs:392`): `highway=busway width:lanes=3|3|3 shoulder=right est_width=5 lanes:backward=2 parking:right:capacity=4 motorcar:lanes=yes|no|yes turn=left turn:lanes:backward=left|through`. It is found alone and left out, as there is no output to compare. The port stops on it with the same error (`dist_along -4m is negative`, checked once by hand).
- Muv's own unit tests of the parts it rests on, translated (`MuvUnitTests`, 10 tests): the subtag order (`iter_tags`), numbers, quantities, parentheses, conditionals, separated values, the hierarchy, opening hours.

## The Rust's HashMap order

The Rust is not deterministic where two crossings (or traffic signals) set the same end of one road: streets_reader applies them iterating a `HashMap`, random per process, and the last one sets the stop line. With 16 runs sampled, an early version of the test missed the port's result on 15/19809/10242 once (its 6 results come out 27 to 45 times in 200 runs each). The tests no longer sample. The port records every road end set by several points of one map (`HashMapOrder`, `Sources/Streets/Reader/HashMapOrder.swift`, used only by tests) and computes its four outputs for every choice of the last point at each. A case passes only if every Rust result equals one of those (16 live runs where the order changes the result, or every stored result): each Rust order is reproduced exactly, and "differs from all runs" fails. Where the order changes the result (all crossings, no signal):

| Case | Contested road ends (way) | Port results | Rust results in 200 runs (2026-10-25, when the oracle was stored) |
|---|---|---|---|
| `roosevelt_cycletrack` | end of road 106 (621283289), 2 crossings | 2 | 2 |
| 15/19809/10242 | end of road 140 (25069289) 2, start of road 1113 (666456349) 2, end of road 27 (8810805) 3 crossings | 6 | 6, the same 6 lane markings (counts 43, 27, 31, 34, 20, 45), the other outputs constant |
| 15/19808/10243 | start of road 1 (22323173), end of road 632 (209618700), 2 crossings each | 2 | 2, the same 2 (99, 101) |
| 15/19810/10243 | end of road 606 (500290236), 2 crossings | 2 | 2 |

The region and the other tiles have a contested end whose choices give the same output (1 port result).

## Speed

Release builds, Apple silicon.

| Run | Rust | Port, release |
|---|---|---|
| Moscow region, the four outputs | 0.8 s | 2.17 s |
| One tile, unclipped | | 0.71 to 1.11 s |

The legal speed table of `MuvLanes` is one text decoded at first use, not dictionary literals: those cost the optimised build of `MuvLanes` 40 s (65 s against 25 s).

## Commits

In ImmersiveMapEditor: `35e8f39` Earcut. `83580c7` CountryBoundaries. `3beda24`, `1984e35` OSMReader. `90462b0` GeoAlgorithms. `7904438` StreetGeom. `c23063a` Streets with the parity tests. `b01ae76` the remaining transformations. `4936c3d` MuvLanes and osm2lanes reading through it. Extracted into this package at `1d27d0f`.

## Left

- A way to check `ZipSidepaths` and `RemoveDisconnectedRoads` against the Rust (the binary does not run them).
- PBF input (osm2streets's `frederiksted`) is not ported: only XML is read.
- The tests of geo over `geo-test-fixtures` (convex hulls of `poly1` and `poly2`, simplification of `norway_main` and `vw_orig`, the boolean operation of issue 894) are disabled: that crate's data is not carried by this package.
