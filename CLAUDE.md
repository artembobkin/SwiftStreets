# SwiftStreets

A Swift port of osm2streets (with streets_reader and osm2lanes, rev `fc119c4`) and of the Rust code it stands on, each a target of its own. It reads OSM XML and writes the same four GeoJSON documents as the Rust, byte for byte. Public repository `github.com/artembobkin/SwiftStreets`. It was written inside ImmersiveMapEditor (whose tile pipeline seeds its road documents through it) and extracted here at that repository's commit `1d27d0f`: the editor depends on this package, so target and module names never change.

## Layout

`Sources/`, one folder per target, each with its licence file:

- `Earcut`: earcutr 0.4.3 (ISC, `LICENSE`). Linked lists, ear slicing, holes, the legacy entry points.
- `GeoAlgorithms`: geo 0.27 and geo-types 0.7, plus rstar, polylabel and petgraph where used (MIT, `LICENSE`). `Types/`, `Algorithms/` (area, centroid, contains, intersects, hull, closest point, simplify, polylabel, winding), `BoolOps/` and `Sweep/` (the boolean operations), `Robust/` (exact predicates), `Support/` (Rust's slice sort, ordering, binary heap, `next_after`).
- `StreetGeom`: geom, rev `9bb49fc` (Apache-2.0, `NOTICE`). `Units/` (`Pt2D` rounded as geom rounds, `Distance`, `Angle`, `Speed`), `Shapes/` (`Line`, `PolyLine` with its shifts and slices, `Ring`, `Polygon`, tessellation), `GPS/` (bounds, GeoJSON polygons), `JSON/` (a JSON value and parser, and Rust's number formatting: serde_json's ryu, `Display`, `Debug`).
- `OSMReader`: osm-reader, rev `7892405` (Apache-2.0, `NOTICE`). OSM XML only.
- `CountryBoundaries`: country-boundaries 1.2.0 (Apache-2.0, `NOTICE`, the data ODbL), the embedded 60x30 raster (`BoundariesData.swift`) and the driving side.
- `MuvLanes`: Muv's lane reading, muv-osm rev `2404d40` (MPL-2.0, `LICENSE`, every file with the MPL notice), with MIT translations of rustc-hash, hashbrown and opening-hours-syntax inside.
- `Streets`: osm2streets, streets_reader and osm2lanes, rev `fc119c4`, and abstutil's `Tags` (Apache-2.0, `NOTICE`). `Reader/` (streets_reader, and `HashMapOrder`, the tests' handle on the Rust's HashMap order), `Lanes/` (osm2lanes), `Network/`, `Geometry/` (intersection polygons), `Operations/`, `Transform/`, `Render/` (the four GeoJSON outputs).

`Tests/StreetsTests/` (swift-testing), a folder per target, and:

- `Parity/`: the port against the Rust. `Oracle` (the live binary, `OSM2STREETS_CLI`), `ParityCase` (an input folder), `ParityRun` (the port over every HashMap order, a live run), `FrozenRecord` (the stored answers), `StreetsParityTests` (live, frozen and committed-geometry suites), `SyntheticWays` (one way per tag set across a box), `FreezeOracle` (writes the stored answers), `GeoJSONComparison`, `OverpassXML`.
- `Support/Fixtures.swift`: the fixtures folder, read through `#filePath`, and LZMA decompression.
- `Fixtures/` (left out of the target in `Package.swift`): osm2streets's test cases, the Moscow OSM extracts, the earcutr and country-boundaries files, and `rust/`, the Rust's stored results. Its `NOTICE` gives the terms of each.

`Docs/PortingParity.md` (what was compared and how) and `Docs/PortingStreetsProgress.md` (how the port was made, its decisions, the numbers).

## Rules

- **Parity with the pinned Rust.** The port follows osm2streets `fc119c4`, geom `9bb49fc`, osm-reader `7892405`, muv-osm `2404d40`, geo 0.27, earcutr 0.4.3, country-boundaries 1.2.0: the same algorithm, constants, order of operations, tie-breaking, floating point steps and the Rust's own bugs. Improve nothing that changes an output. A change of revision is a new port, checked again in full.
- **Byte-identical output.** The four GeoJSON outputs must equal the Rust's text exactly. Never loosen a comparison: no tolerance, no normalising, no skipping a case or an output to make a test pass. A difference is a bug in the port until it is explained in `Docs/PortingParity.md`.
- **The nondeterminism rule.** The Rust applies crossings and traffic signals in `HashMap` order, random per process. The tests never sample it: the port enumerates every order at every contested road end (`HashMapOrder`), and each Rust result (every live run, every stored result) must be one of the port's results. When freezing, store every distinct Rust result seen (200 runs where the order matters).
- **The stored oracle is the Rust's.** `Fixtures/rust/` is written only by `FreezeOracle` from a real binary, never by hand and never from the port's own output. Add a committed input together with its stored answers.
- **Licences per target.** Each target keeps its licence file and the notices in its files. `MuvLanes` files (and `MuvUnitTests.swift`) stay under the MPL-2.0 with their headers: new code translated from Muv goes there, other code does not. A file translated from an Apache-2.0 crate goes into that crate's target, whose `NOTICE` names the revision. Test data keeps its attribution (`Fixtures/NOTICE`: map data © OpenStreetMap contributors, ODbL). The project is "a Swift port of osm2streets", never called osm2streets.
- **No dependencies, Swift only.** No package dependencies and no C, C++ or Rust in the package. The Rust binary is an external oracle, never built or run by `swift build`. No AppKit or UIKit: the package builds for macOS, iOS and visionOS.
- **The public API** keeps the Rust's names in Swift's style (`osm_to_street_network` is `StreetNetwork.fromOSM`), so the port reads side by side with the original.

## Checking

- `swift build` and `swift build -c release` with no warnings.
- `swift test` and `swift test -c release -Xswiftc -enable-testing` (the tests use `@testable import`), both passing. Run them also with the live oracle when a binary is at hand: `OSM2STREETS_CLI=/path/to/osm2streets-cli`, and `SWIFTSTREETS_EXTRA_CASES` for more input folders.
- Say what ran and what came out (the counts of tests passed, skipped and failed).

## Writing

- English in every file: code, comments, logs, documentation, commit messages.
- No em dash (U+2014) and no semicolon joining two clauses in prose: two sentences, a comma, a colon or parentheses.
- Swift naming: types, targets, folders and files in UpperCamelCase (a file named after the type it holds), everything else in lowerCamelCase. Every file starts with a doc comment of what it is and what it ports.
- Commits end with `Co-Authored-By:` the model that wrote them. The repository is public: no secrets, no personal data, no absolute home paths.
