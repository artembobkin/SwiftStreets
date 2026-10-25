# Porting parity

What was compared, on what data, what matched, and every difference with its reason. The record of the port of osm2streets to Swift, 2026-10-25, made in the package where the port was written (ImmersiveMapEditor, up to its commit `1d27d0f`) and carried here with the code.

## The bar

`Streets` (osm2streets, streets_reader and osm2lanes, rev `fc119c4`) with the targets under it (`StreetGeom`, `GeoAlgorithms`, `Earcut`, `OSMReader`, `CountryBoundaries`, `MuvLanes`) was compared with a Rust command line build of the same revision, `osm2streets-cli`, the port reading every lane itself. The bar was one to one: the four GeoJSON outputs byte-identical as text. No tolerance was used. (The comparison helper also reports numbers within 1e-9 degrees, but only to say where two outputs differ: a case passes on equal text alone.)

The binary does what osm2streets's own test runner does, with the configuration of the tile pipeline the port was made for:

1. `streets_reader::osm_to_street_network(input, clip, cfg)` with `MapConfig::default()`, `inferred_sidewalks = true` and `inferred_kerbs = true`, the clip being the one polygon of a GeoJSON file, or none;
2. `apply_transformations(Transformation::standard_for_clipped_areas())`;
3. `to_geojson`, `to_lane_polygons_geojson`, `to_lane_markings_geojson`, `to_intersection_markings_geojson`, each with `Filter::All`, written as `plain.geojson`, `lanes.geojson`, `lane_markings.geojson` and `intersection_markings.geojson`.

It was built against osm2streets and streets_reader at `fc119c4`, geom at `9bb49fc`, abstutil (abstreet) at `ca1fb9a`, osm-reader at `7892405`, muv-osm at `2404d40`, release profile, arm64.

## Streets

Measured 2026-10-25, `swift test -c release -Xswiftc -enable-testing`. Details and the tag-set tests of `MuvLanes` in `Docs/PortingStreetsProgress.md`.

| Compared | Data | Result |
|---|---|---|
| The four outputs (plain, lanes, lane markings, intersection markings) | osm2streets's 29 XML test cases | 29 of 29 identical in all four |
| The same | Moscow, a 2x2 block of z15 tiles with its clip (4874 roads, 943 tag sets) | identical in all four (9516, 7557, 58360, 229 features) |
| The same | five Moscow z15 tiles, unclipped | identical, two tiles' lane markings equal to one of the Rust's own results (see below) |
| `to_geojson`, `MapConfig::default()`, invariants checked | the committed `geometry.json` of the 29 cases | 29 of 29 identical |
| The four outputs | synthetic ways: 280 hand-written and 400 random tag sets in each of 10 countries | 20 of 20 identical (one random way left out in FR: the Rust panics on it) |

In the tile pipeline the port was made for, seeding a road document through the port instead of the binary gave the same document and byte-identical outputs over the 2x2 block.

## Accepted difference

None in the port. The Rust is not deterministic where two crossings or traffic signals set the same road end (streets_reader iterates a `HashMap`, random per process). The tests do not sample this: the port computes its outputs for every order of each contested road end (`HashMapOrder`), and every Rust result must equal one of them (16 live runs where the order changes the result). Measured over 200 Rust runs: tile 15/19809/10242 gives exactly the port's 6 results (three contested road ends, 2 by 2 by 3 crossings), 15/19808/10243 exactly its 2. Details in `Docs/PortingStreetsProgress.md`.

## The stored oracle

So that a clone proves parity without Rust, the Rust's answers on every committed input are stored (`Tests/StreetsTests/Fixtures/rust/`, written by `FreezeOracle` from the same binary on 2026-10-25): each distinct result of its runs, as the SHA-256, length and feature count of its four outputs. The frozen tests compute the port's results (over every HashMap order, as the live tests do) and require each stored Rust result to be one of them, byte for byte. The live tests (`OSM2STREETS_CLI` set) still run the binary itself on the same inputs. See `README.md`, "Tests".

| Inputs | Rust runs per input | Distinct Rust results |
|---|---|---|
| osm2streets's 29 XML cases | 16, and 200 for `roosevelt_cycletrack` | 1, and 2 for `roosevelt_cycletrack` (the port's 2) |
| Moscow region and five tiles | 16, and 200 for tiles 15/19808/10243, 15/19809/10242 and 15/19810/10243 | 1, and 2, 6 and 2 for those tiles (the port's 2, 6 and 2) |
| Synthetic ways, 20 sets in 10 countries | 16 | 1 each (one random way in FR left out: the Rust panics on it) |
