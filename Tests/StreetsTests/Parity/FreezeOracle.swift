/// Writes the Rust's stored answers (`Fixtures/rust/`) from a live binary.
/// Not a check: it runs only when asked,
///
///     OSM2STREETS_CLI=/path/to/osm2streets-cli SWIFTSTREETS_FREEZE=1 \
///         swift test -c release -Xswiftc -enable-testing --filter FreezeOracle
///
/// For each committed input the Rust runs `SWIFTSTREETS_FREEZE_RUNS` times
/// (16 by default), and 200 times (`SWIFTSTREETS_FREEZE_CONTESTED_RUNS`)
/// where the order of its HashMaps changes the port's result or the Rust's
/// own runs differ. Every distinct result is stored. A result the port does
/// not explain fails the test, and is stored all the same, so that the
/// frozen tests fail on it too.

import Foundation
import Testing

private let environment = ProcessInfo.processInfo.environment
private let freezing = environment["SWIFTSTREETS_FREEZE"] == "1"
private let baseRuns = environment["SWIFTSTREETS_FREEZE_RUNS"].flatMap(Int.init) ?? 16
private let contestedRuns = environment["SWIFTSTREETS_FREEZE_CONTESTED_RUNS"].flatMap(Int.init) ?? 200

@Suite(.serialized, .enabled(if: freezing && Oracle.available, "set SWIFTSTREETS_FREEZE=1 and OSM2STREETS_CLI to freeze the oracle"))
struct FreezeOracle {
    @Test(arguments: ParityCase.osm2streets + ParityCase.moscow)
    func freezeCase(_ c: ParityCase) throws {
        let bytes = try c.xmlBytes()
        let input = try c.xmlFile(bytes)
        let port = try PortResults.compute(bytes, clip: c.clipPoints())
        let ours = Set(port.variants.map(digest))
        let work = Oracle.scratch.appendingPathComponent("freeze").appendingPathComponent(c.name)
        var results: [ResultDigest] = []
        var runs = 0
        func runOnce() throws {
            let out = try Oracle.run(input: input, clip: c.clipFile, out: work)
            let d = digest(Oracle.outputs.map { out[$0]! })
            if !results.contains(d) { results.append(d) }
            runs += 1
        }
        for _ in 0..<baseRuns { try runOnce() }
        if port.variants.count > 1 || results.count > 1 {
            while runs < contestedRuns { try runOnce() }
        }
        try FrozenRecord(rustRuns: runs, results: results).save(c.name)
        let unexplained = results.filter { !ours.contains($0) }.count
        print("FREEZE \(c.name): \(runs) Rust runs, \(results.count) distinct results, \(port.variants.count) port results, "
              + "\(unexplained) not the port's")
        #expect(unexplained == 0)
    }

    @Test(arguments: MuvBoxes.all)
    func freezeMuv(_ box: SyntheticBox) throws {
        let work = Oracle.scratch.appendingPathComponent("freeze/muv_\(box.name)")
        for (name, allSets) in [(MuvBoxes.handName(box), MuvTagSets.handWritten), (MuvBoxes.randomName(box), MuvBoxes.randomSets(box))] {
            var sets = allSets
            var rejected = Set<Int>()
            do {
                _ = try SyntheticWays.rustOutputs(sets, in: box, work: work)
            } catch OracleError.failed {
                rejected = try SyntheticWays.rustRejected(sets, in: box, work: work.appendingPathComponent("alone"))
                sets = MuvBoxes.without(sets, rejected)
            }
            var results: [ResultDigest] = []
            for _ in 0..<baseRuns {
                let d = digest(try SyntheticWays.rustOutputs(sets, in: box, work: work))
                if !results.contains(d) { results.append(d) }
            }
            try FrozenRecord(rustRuns: baseRuns, rustRejected: rejected.isEmpty ? nil : rejected.sorted(), results: results)
                .save(name)
            let mine = digest(try SyntheticWays.portOutputs(sets, in: box))
            print("FREEZE \(name): \(baseRuns) Rust runs, \(results.count) distinct results, \(rejected.count) tag sets left out")
            #expect(results == [mine])
        }
    }
}
