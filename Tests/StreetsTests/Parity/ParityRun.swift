/// One parity case: the Swift port's four GeoJSON outputs over an OSM file
/// and clip, against the Rust binary's (live) or its stored results.
///
/// The Rust is not always deterministic: streets_reader iterates traffic
/// signals and crossings in `HashMap` order, random per process, and when two
/// of them set the same road end the last one wins. The port records those
/// road ends (`HashMapOrder`) and computes its result for every choice of the
/// last one at each. A case passes when every Rust result (each of 16 live
/// runs where the order changes the result, else one, or each stored one)
/// equals one of the port's results: its order is reproduced exactly, so
/// the test does not depend on which orders the Rust happens to take.

import Foundation
import StreetGeom
@testable import Streets

/// The port's results for one input: in its own order, and over every order of the Rust's HashMaps.
struct PortResults {
    var outputs: [String]
    var variants: Set<[String]>
    var seconds: Double
    var tagSets: Int
    var roads: Int
    var intersections: Int
    /// Road ends where the order of the Rust's HashMaps decides the result.
    var contestedDetail: [String]

    /// The configuration of the Rust binary: inferred sidewalks and kerbs.
    static func parityConfig() -> MapConfig {
        var cfg = MapConfig()
        cfg.inferredSidewalks = true
        cfg.inferredKerbs = true
        return cfg
    }

    /// The four outputs of the port, the signals and crossings applied in `order`.
    static func outputs(_ bytes: [UInt8], _ clipPts: [LonLat]?, _ config: MapConfig,
                        _ order: HashMapOrder?) throws -> (StreetNetwork, [String]) {
        var streets = try StreetNetwork.fromOSM(bytes, clip: clipPts, config: config, hashMapOrder: order)
        streets.applyTransformations(Transformation.standardForClippedAreas())
        return (streets, [streets.toGeoJSON(.all), streets.toLanePolygonsGeoJSON(.all),
                          try streets.toLaneMarkingsGeoJSON(.all), streets.toIntersectionMarkingsGeoJSON(.all)])
    }

    static func compute(_ bytes: [UInt8], clip clipPts: [LonLat]?) throws -> PortResults {
        let config = parityConfig()
        let tagSets = try RoadWays.collect(bytes, clip: clipPts, config: config).tagSets.count
        let clock = ContinuousClock()
        let started = clock.now
        let order = HashMapOrder()
        let (streets, outputs) = try Self.outputs(bytes, clipPts, config, order)
        let elapsed = clock.now - started

        // Every order the Rust's HashMaps can take: for each road end that
        // several signals, or several crossings, set, each of them last.
        let contested = order.contested
        var variants: Set<[String]> = [outputs]
        if !contested.isEmpty {
            let combinations = contested.reduce(1) { $0 * $1.1.count }
            precondition(combinations <= 4096, "\(combinations) orders to try")
            for c in 0..<combinations {
                var rest = c
                let o = HashMapOrder()
                for (group, pts) in contested {
                    let pt = pts[rest % pts.count]
                    rest /= pts.count
                    if group.map == "signals" { o.signalsLast.insert(pt) } else { o.crossingsLast.insert(pt) }
                }
                variants.insert(try Self.outputs(bytes, clipPts, config, o).1)
            }
        }
        return PortResults(
            outputs: outputs, variants: variants,
            seconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18,
            tagSets: tagSets, roads: streets.roads.count, intersections: streets.intersections.count,
            contestedDetail: contested.map { g, pts in
                "\(g.map) at the \(g.atEnd ? "end" : "start") of \(g.road) (\(pts.count) points, way \(streets.roads[g.road].map { "\($0.osmIDs.map(\.id))" } ?? "removed"))"
            })
    }

    var summary: String {
        "\(String(format: "%.2f", seconds)) s: \(roads) roads, \(intersections) intersections, \(tagSets) tag sets"
            + (contestedDetail.isEmpty ? "" : "; \(contestedDetail.count) road ends set by several signals or crossings (\(contestedDetail.joined(separator: ", "))), \(variants.count) port results over their orders")
    }
}

/// A live run: the port against the Rust binary.
struct ParityRun {
    var name: String
    var port: PortResults
    /// The port's outputs against the Rust's first run, for the summary.
    var comparisons: [String: GeoJSONComparison] = [:]
    /// Distinct Rust results seen, and in how many runs.
    var rustVariants = 1
    var rustRuns = 1
    /// Every Rust run equals the port's result for one of the orders.
    var everyRustRunExplained = false

    var allMatch: Bool { everyRustRunExplained }

    static func run(_ c: ParityCase) throws -> ParityRun {
        let bytes = try c.xmlBytes()
        let input = try c.xmlFile(bytes)
        let clip = c.clipFile
        let work = Oracle.scratch.appendingPathComponent(c.name)
        let expected = try Oracle.run(input: input, clip: clip, out: work.appendingPathComponent("rust"))
        let port = try PortResults.compute(bytes, clip: c.clipPoints())
        var result = ParityRun(name: c.name, port: port)
        let swiftDir = work.appendingPathComponent("swift")
        try FileManager.default.createDirectory(at: swiftDir, withIntermediateDirectories: true)
        for (k, text) in zip(Oracle.outputs, port.outputs) {
            try text.write(to: swiftDir.appendingPathComponent("\(k).geojson"), atomically: true, encoding: .utf8)
            result.comparisons[k] = GeoJSONComparison.compare(expected: expected[k]!, actual: text)
        }

        // The Rust's runs must each be one of the port's results: its order
        // reproduced, not hoped for. Where the order changes the result, the
        // Rust runs 16 times.
        let first = Oracle.outputs.map { expected[$0]! }
        var rustVariants: Set<[String]> = [first]
        var explained = port.variants.contains(first)
        if port.variants.count > 1 || !explained {
            for k in 2...16 {
                let again = try Oracle.run(input: input, clip: clip, out: work.appendingPathComponent("rust\(k)"))
                let a = Oracle.outputs.map { again[$0]! }
                rustVariants.insert(a)
                explained = explained && port.variants.contains(a)
                result.rustRuns = k
            }
        }
        result.rustVariants = rustVariants.count
        result.everyRustRunExplained = explained
        return result
    }

    var summary: String {
        var s = "\(name) (\(port.summary))"
        for k in Oracle.outputs {
            let c = comparisons[k]!
            s += "; \(k) \(c.featuresActual)/\(c.featuresExpected) features, "
            s += c.identicalText ? "identical" : (c.matches ? "equal within 1e-9 (\(c.numbersWithinTolerance) numbers)"
                : "differs from the first Rust run at \(c.firstDifference!)")
        }
        if !port.contestedDetail.isEmpty || rustRuns > 1 {
            s += "; the Rust gave \(rustVariants) distinct results in \(rustRuns) runs, "
            s += everyRustRunExplained ? "each one of the port's" : "not all of them the port's"
        }
        return s
    }
}
