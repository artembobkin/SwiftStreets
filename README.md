# SwiftStreets

A Swift port of [osm2streets](https://github.com/a-b-street/osm2streets) (with its streets_reader and osm2lanes, revision `fc119c4`) and of the Rust code it stands on. It reads OpenStreetMap XML and reconstructs the street network: roads with their lanes, intersections with their polygons, lane and intersection markings, written as the same GeoJSON the Rust writes. Its output is byte-identical to the Rust at the pinned revisions on osm2streets's own test cases and on real city data (see Parity).

Pure Swift, no dependencies, no C, C++ or Rust. Swift 6 tools (the Swift 5 language mode), macOS 15, iOS 18, visionOS 2.

## Installation

Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/artembobkin/SwiftStreets.git", from: "0.1.0"),
],
targets: [
    .target(name: "MyTarget", dependencies: [
        .product(name: "Streets", package: "SwiftStreets"),
        .product(name: "StreetGeom", package: "SwiftStreets"),
    ]),
]
```

Every building block is a library product of its own and can be used alone:

| Product | What it is | Port of |
|---|---|---|
| `Streets` | the street network from OSM: roads, lanes, intersections, transformations, the GeoJSON outputs | osm2streets, streets_reader, osm2lanes (rev `fc119c4`) |
| `StreetGeom` | A/B Street's geometry: points, distances, angles, polylines and their shifts, rings, polygons, tessellation, GPS bounds, JSON as serde_json writes it | geom (rev `9bb49fc`) |
| `GeoAlgorithms` | the algorithms of geo osm2streets calls: boolean operations and their sweep, area, centroid, contains, intersects, convex hull, closest point, simplification, polylabel, robust predicates | geo 0.27, geo-types 0.7 |
| `Earcut` | polygon triangulation | earcutr 0.4.3 (Mapbox's earcut) |
| `OSMReader` | OSM XML into nodes, ways and relations | osm-reader (rev `7892405`) |
| `CountryBoundaries` | the countries at a point, with the embedded 60x30 boundary raster, and the driving side of a country | country-boundaries 1.2.0 |
| `MuvLanes` | Muv's reading of lanes from OSM tags | muv-osm (rev `2404d40`) |

## Usage

```swift
import Foundation
import StreetGeom
import Streets

// OSM XML in, the road network out.
let osm = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
// An optional clip: one GeoJSON polygon in WGS84.
let clip = try CommandLine.arguments.dropFirst(2).first.map {
    try LonLat.parseGeoJSONPolygons(String(contentsOfFile: $0, encoding: .utf8))[0].0
}

var config = MapConfig()
config.inferredSidewalks = true
var streets = try StreetNetwork.fromOSM(Array(osm), clip: clip, config: config)
streets.applyTransformations(Transformation.standardForClippedAreas())

print("\(streets.roads.count) roads, \(streets.intersections.count) intersections")
for road in streets.roads.values.prefix(3) {
    print(road.osmIDs.map(\.id), road.laneSpecsLTR.map(\.lt))
}
let plain = streets.toGeoJSON(.all)                 // roads and intersections as polygons
let lanes = streets.toLanePolygonsGeoJSON(.all)     // every lane, with its type and width
let markings = try streets.toLaneMarkingsGeoJSON(.all)
try plain.write(toFile: "plain.geojson", atomically: true, encoding: .utf8)
print(lanes.count, markings.count)
```

The names follow the Rust's in Swift's style (`osm_to_street_network` is `StreetNetwork.fromOSM`, `to_lane_polygons_geojson` is `toLanePolygonsGeoJSON`), so the port reads side by side with the original.

## Scope

Ported: everything osm2streets runs from OSM XML to its four GeoJSON outputs (`to_geojson`, `to_lane_polygons_geojson`, `to_lane_markings_geojson`, `to_intersection_markings_geojson`): streets_reader (reading, clipping, splitting ways, traffic signals and crossings, turn restrictions), osm2lanes reading every lane through Muv, the country and driving side, the road and intersection geometry, and the transformations (the standard sets and the rest). Under it, the parts of geom, geo, earcutr, osm-reader, country-boundaries and muv-osm it reaches.

Not ported:

- PBF input (osm-reader reads it, this port reads XML only).
- osm2streets's block tracing (`block.rs`), its debug output (`to_debug_geojson`), and osm2lanes's lane editing (`edit/`: adding bike lanes, new lanes, changing one-ways).
- `MergeDualCarriageways` only writes debugging output in the Rust: here it is a no-op.
- osm2streets's other front ends (the JavaScript, Python and Java bindings, the street-explorer web app).
- Evaluating conditional restrictions at a date (`MapConfig` has no date: osm2lanes evaluates conditions only for one).
- `ZipSidepaths` and `RemoveDisconnectedRoads` are ported but not checked against the Rust (the oracle binary does not run them).

## Parity

The port was compared with a Rust command line build of osm2streets `fc119c4` (geom `9bb49fc`, osm-reader `7892405`, muv-osm `2404d40`), with inferred sidewalks and kerbs and the transformations for clipped areas. The bar was byte-identical GeoJSON text, no tolerance (`Docs/PortingParity.md`, `Docs/PortingStreetsProgress.md`):

| Compared | Data | Result |
|---|---|---|
| The four outputs | osm2streets's 29 XML test cases | 29 of 29 identical in all four |
| The same | Moscow, a 2x2 block of z15 tiles with its clip (4874 roads, 943 tag sets) | identical in all four (9516, 7557, 58360, 229 features) |
| The same | five Moscow z15 tiles, unclipped (1389 to 2091 roads each) | identical (two tiles' lane markings equal to one of the Rust's own results, see below) |
| `to_geojson`, `MapConfig::default()`, invariants checked | the committed `geometry.json` of the 29 cases | 29 of 29 identical |
| The four outputs | synthetic ways: 280 hand-written and 400 random tag sets in each of 10 countries | 20 of 20 identical |

The Rust itself is not deterministic where two crossings or traffic signals set the same road end (streets_reader iterates a `HashMap` in a random order per process). The port computes its result for every such order, and every Rust result must be one of them, exactly.

## Tests

```sh
swift test                                       # debug
swift test -c release -Xswiftc -enable-testing   # optimised, much faster (the tests use @testable import)
```

The tests (swift-testing, one target `StreetsTests`) are self-contained. Besides the unit tests of each target (translated from the Rust crates' own tests where they exist), they hold:

- **The stored oracle.** For every committed input (osm2streets's 29 XML cases, the Moscow region and five tiles, the synthetic ways) the Rust binary's results are stored in `Tests/StreetsTests/Fixtures/rust/`: every distinct result seen over its runs, as the SHA-256, length and feature count of each of the four outputs. `StreetsFrozenTests` and `MuvLanesFrozenTests` compute the port's outputs and require each stored Rust result to be one of the port's, byte for byte. These always run.
- **The live oracle.** With `OSM2STREETS_CLI` naming a build of the binary described in `Docs/PortingParity.md`, `StreetsParityTests` and `MuvLanesOracleTests` run it on the same inputs and compare. Folders of your own can be added with `SWIFTSTREETS_EXTRA_CASES` (colon-separated, each holding `input.osm` or an Overpass `osm.json`, and optionally `boundary.json` or `clip.geojson`). Without the variable they are skipped.

```sh
OSM2STREETS_CLI=/path/to/osm2streets-cli swift test -c release -Xswiftc -enable-testing
OSM2STREETS_CLI=/path/to/osm2streets-cli SWIFTSTREETS_FREEZE=1 \
    swift test -c release -Xswiftc -enable-testing --filter FreezeOracle   # store the oracle again
```

## License

The package's own code (its manifest, test harness and documentation) is under the MIT License (`LICENSE`). The ports keep the licences of the code they translate, each in its source folder:

- `Earcut`: earcutr 0.4.3, ISC (`Sources/Earcut/LICENSE`).
- `GeoAlgorithms`: geo 0.27, geo-types 0.7, rstar, polylabel and petgraph where used, MIT (`Sources/GeoAlgorithms/LICENSE`).
- `StreetGeom` (geom, rev `9bb49fc`), `OSMReader` (osm-reader, rev `7892405`), `CountryBoundaries` (country-boundaries 1.2.0) and `Streets` (osm2streets, streets_reader and osm2lanes, rev `fc119c4`, and abstutil's `Tags`): Apache-2.0, each folder's `NOTICE` saying what it translates. The licence text is in `LICENSES/Apache-2.0.txt`. The boundary data `CountryBoundaries` carries is © OpenStreetMap contributors, under the ODbL 1.0.
- `MuvLanes`: Muv's lane reading (muv-osm, rev `2404d40`), MPL-2.0, a file-level licence: those files (and the translated Muv unit tests, `Tests/StreetsTests/MuvLanes/MuvUnitTests.swift`) stay under the MPL. It also carries MIT translations of rustc-hash, hashbrown and opening-hours-syntax (`Sources/MuvLanes/LICENSE`).

The test data keeps its own terms (`Tests/StreetsTests/Fixtures/NOTICE`): osm2streets's test cases (Apache-2.0), the files of earcutr (ISC) and country-boundaries (Apache-2.0, data ODbL), and OpenStreetMap extracts of Moscow. Map data © OpenStreetMap contributors, ODbL.

This is an independent port, not the osm2streets project. The original is by Dustin Carlino and the A/B Street contributors.
