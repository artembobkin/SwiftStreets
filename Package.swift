// swift-tools-version:6.0
import PackageDescription

/// SwiftStreets: a Swift port of osm2streets (rev fc119c4) and of what it
/// stands on, each a target of its own, with its own licence in its folder.
let package = Package(
    name: "SwiftStreets",
    platforms: [.macOS(.v15), .iOS(.v18), .visionOS(.v2)],
    products: [
        .library(name: "Streets", targets: ["Streets"]),
        .library(name: "Earcut", targets: ["Earcut"]),
        .library(name: "GeoAlgorithms", targets: ["GeoAlgorithms"]),
        .library(name: "StreetGeom", targets: ["StreetGeom"]),
        .library(name: "OSMReader", targets: ["OSMReader"]),
        .library(name: "CountryBoundaries", targets: ["CountryBoundaries"]),
        .library(name: "MuvLanes", targets: ["MuvLanes"]),
    ],
    targets: [
        // earcutr 0.4.3 (ISC): polygon triangulation.
        .target(name: "Earcut", path: "Sources/Earcut", exclude: ["LICENSE"]),
        // geo 0.27 and geo-types 0.7 (MIT): the algorithms osm2streets uses.
        .target(name: "GeoAlgorithms", path: "Sources/GeoAlgorithms", exclude: ["LICENSE"]),
        // geom (rev 9bb49fc, Apache-2.0): A/B Street's shapes, units and JSON.
        .target(name: "StreetGeom", dependencies: ["GeoAlgorithms", "Earcut"], path: "Sources/StreetGeom", exclude: ["NOTICE"]),
        // osm-reader (rev 7892405, Apache-2.0): OSM XML.
        .target(name: "OSMReader", path: "Sources/OSMReader", exclude: ["NOTICE"]),
        // country-boundaries 1.2.0 (Apache-2.0, its data ODbL): the country and driving side of a point.
        .target(name: "CountryBoundaries", path: "Sources/CountryBoundaries", exclude: ["NOTICE"]),
        // Muv's reading of lanes from OSM tags (muv-osm, rev 2404d40), the one
        // MPL-2.0 target: its files stay under the MPL.
        .target(name: "MuvLanes", path: "Sources/MuvLanes", exclude: ["LICENSE"]),
        // osm2streets, streets_reader and osm2lanes (rev fc119c4, Apache-2.0).
        .target(name: "Streets", dependencies: ["StreetGeom", "GeoAlgorithms", "OSMReader", "CountryBoundaries", "MuvLanes"],
                path: "Sources/Streets", exclude: ["NOTICE"]),
        // The ports against their originals: unit tests, the upstream test
        // fixtures, and the Rust osm2streets's outputs, stored (Tests/StreetsTests/Fixtures)
        // or live when OSM2STREETS_CLI names the binary.
        .testTarget(name: "StreetsTests", dependencies: ["Streets", "StreetGeom", "GeoAlgorithms", "Earcut", "OSMReader",
                                                         "CountryBoundaries", "MuvLanes"],
                    path: "Tests/StreetsTests", exclude: ["Fixtures"]),
    ],
    swiftLanguageModes: [.v5]
)
