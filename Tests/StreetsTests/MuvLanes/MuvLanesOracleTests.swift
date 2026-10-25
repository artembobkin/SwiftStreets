/// MuvLanes against the Rust: synthetic ways with a wide set of tag sets
/// (written by hand to reach every part of Muv's lane reading, and drawn at
/// random from a vocabulary of lane keys with a fixed seed) in boxes in
/// several countries, read by the Rust osm2streets and by the port. The
/// four outputs must be identical, the lanes (with their `muv` property,
/// Muv's serde output) above all.
///
/// `MuvLanesOracleTests` runs the Rust binary (`OSM2STREETS_CLI`) and skips
/// without it. `MuvLanesFrozenTests` compares the port with the Rust's
/// stored results (`Fixtures/rust/muv/`) and always runs.

import Foundation
import Testing

enum MuvBoxes {
    static let all: [SyntheticBox] = [
        .around("RU", lon: 37.61, lat: 55.75),
        .around("DE", lon: 13.40, lat: 52.52),
        .around("GB", lon: -0.12, lat: 51.50),
        .around("US", lon: -74.00, lat: 40.71),
        .around("FR", lon: 2.35, lat: 48.85),
        .around("NL", lon: 4.90, lat: 52.37),
        .around("IE", lon: -6.26, lat: 53.35),
        .around("AU", lon: 151.21, lat: -33.87),
        .around("AT", lon: 16.37, lat: 48.21),
        .around("BE", lon: 4.35, lat: 50.85),
    ]

    /// The random tag sets of a box, seeded by its name.
    static func randomSets(_ box: SyntheticBox) -> [[(String, String)]] {
        MuvTagSets.random(count: 400, seed: box.name.utf8.reduce(UInt64(7)) { $0 &* 31 &+ UInt64($1) })
    }

    /// The names of a box's stored answers.
    static func handName(_ box: SyntheticBox) -> String { "muv/hand_\(box.name)" }
    static func randomName(_ box: SyntheticBox) -> String { "muv/random_\(box.name)" }

    /// The tag sets without those at the given indices.
    static func without(_ sets: [[(String, String)]], _ rejected: Set<Int>) -> [[(String, String)]] {
        sets.enumerated().filter { !rejected.contains($0.offset) }.map(\.element)
    }
}

@Suite(.serialized, .enabled(if: Oracle.available, "OSM2STREETS_CLI does not name the Rust osm2streets-cli"))
struct MuvLanesOracleTests {
    @Test(arguments: MuvBoxes.all)
    func handWritten(_ box: SyntheticBox) throws {
        let r = try SyntheticWays.compare(MuvTagSets.handWritten, in: box,
                                          work: Oracle.scratch.appendingPathComponent("muv_hand_\(box.name)"))
        print("MUV hand-written \(box.name): \(MuvTagSets.handWritten.count) tag sets, \(r.lanes) lanes, \(r.outputsIdentical)")
        #expect(r.allIdentical, "\(r.firstDifference ?? "no lane differs")")
    }

    @Test(arguments: MuvBoxes.all)
    func random(_ box: SyntheticBox) throws {
        var sets = MuvBoxes.randomSets(box)
        let work = Oracle.scratch.appendingPathComponent("muv_random_\(box.name)")
        // A random way can make the Rust itself panic (geom's `dist_along` of
        // a negative distance): such ways, found one by one, are left out
        // and listed. The port is not run on them, a panic having no output.
        var rejected = Set<Int>()
        let r: SyntheticWays.Result
        do {
            r = try SyntheticWays.compare(sets, in: box, work: work)
        } catch OracleError.failed {
            rejected = try SyntheticWays.rustRejected(sets, in: box, work: work.appendingPathComponent("alone"))
            for k in rejected.sorted() {
                print("MUV random \(box.name): the Rust panics on " + sets[k].map { "\($0.0)=\($0.1)" }.joined(separator: " "))
            }
            sets = MuvBoxes.without(sets, rejected)
            r = try SyntheticWays.compare(sets, in: box, work: work)
        }
        print("MUV random \(box.name): \(sets.count) tag sets, \(r.lanes) lanes, \(r.outputsIdentical); "
              + "left out as the Rust panics: \(rejected.count)")
        #expect(r.allIdentical, "\(r.firstDifference ?? "no lane differs")")
    }
}

@Suite struct MuvLanesFrozenTests {
    @Test(arguments: MuvBoxes.all)
    func handWritten(_ box: SyntheticBox) throws {
        try check(MuvTagSets.handWritten, in: box, name: MuvBoxes.handName(box))
    }

    /// The ways the Rust panics on are left out as the stored answers list them.
    @Test(arguments: MuvBoxes.all)
    func random(_ box: SyntheticBox) throws {
        try check(MuvBoxes.randomSets(box), in: box, name: MuvBoxes.randomName(box))
    }

    private func check(_ allSets: [[(String, String)]], in box: SyntheticBox, name: String) throws {
        let record = try FrozenRecord.load(name)
        let sets = MuvBoxes.without(allSets, Set(record.rustRejected ?? []))
        let mine = digest(try SyntheticWays.portOutputs(sets, in: box))
        print("MUV frozen \(name): \(sets.count) tag sets (\(allSets.count - sets.count) left out as the Rust panics), "
              + "\(record.results.count) stored Rust results of \(record.rustRuns) runs")
        for r in record.results {
            for (k, (e, a)) in zip(Oracle.outputs, zip(r, mine)) {
                #expect(e == a, "\(name) \(k): the Rust stored \(e.summary), the port gives \(a.summary)")
            }
        }
    }
}

extension SyntheticBox: CustomTestStringConvertible {
    var testDescription: String { name }
}
