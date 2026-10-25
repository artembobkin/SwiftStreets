/// Parity of the Swift osm2streets with the Rust, on osm2streets's own test
/// cases, the Moscow data and any folders in `SWIFTSTREETS_EXTRA_CASES`.
///
/// `StreetsFrozenTests` compares the port with the Rust's stored results and
/// always runs. `StreetsParityTests` runs the Rust binary itself, when
/// `OSM2STREETS_CLI` names it, and skips otherwise. Both apply one rule:
/// every Rust result must be byte for byte one of the port's results over
/// the orders of the Rust's HashMaps (`ParityRun`). Each case's summary is
/// printed. Also the committed `geometry.json` of osm2streets's tests,
/// against the port alone.

import Foundation
import StreetGeom
import Streets
import Testing

@Suite(.serialized, .enabled(if: Oracle.available, "OSM2STREETS_CLI does not name the Rust osm2streets-cli"))
struct StreetsParityTests {
    @Test(arguments: ParityCase.osm2streets)
    func osm2streetsCase(_ c: ParityCase) throws { try check(c) }

    /// The 2x2 block of z15 tiles with its clip, and each of five tiles unclipped.
    @Test(arguments: ParityCase.moscow)
    func moscow(_ c: ParityCase) throws { try check(c) }

    @Test(arguments: ParityCase.extra)
    func extra(_ c: ParityCase) throws { try check(c) }

    private func check(_ c: ParityCase) throws {
        let run = try ParityRun.run(c)
        print("PARITY \(run.summary)")
        #expect(run.allMatch, "\(run.summary)")
    }
}

@Suite struct StreetsFrozenTests {
    @Test(arguments: ParityCase.osm2streets)
    func osm2streetsCase(_ c: ParityCase) throws { try check(c) }

    @Test(arguments: ParityCase.moscow)
    func moscow(_ c: ParityCase) throws { try check(c) }

    /// Every committed input has its stored answers.
    @Test func everyCaseIsFrozen() {
        #expect(ParityCase.osm2streets.count == 29)
        #expect(ParityCase.moscow.count == 6)
        for c in ParityCase.osm2streets + ParityCase.moscow {
            #expect(FrozenRecord.exists(c.name), "no stored answers for \(c.name)")
        }
    }

    private func check(_ c: ParityCase) throws {
        let record = try FrozenRecord.load(c.name)
        let port = try PortResults.compute(c.xmlBytes(), clip: c.clipPoints())
        let ours = Set(port.variants.map(digest))
        let unexplained = record.results.filter { !ours.contains($0) }
        print("FROZEN \(c.name) (\(port.summary)); \(record.results.count) stored Rust results of \(record.rustRuns) runs, "
              + (unexplained.isEmpty ? "each one of the port's" : "\(unexplained.count) not the port's"))
        for r in unexplained {
            let mine = digest(port.outputs)
            for (k, (e, a)) in zip(Oracle.outputs, zip(r, mine)) where e != a {
                Issue.record("\(c.name) \(k): the Rust stored \(e.summary), the port gives \(a.summary)")
            }
        }
        #expect(unexplained.isEmpty)
    }
}

/// The committed `geometry.json` of osm2streets's tests, made as its tests
/// make it: the default configuration (no inferred sidewalks), invariants
/// checked, the transformations for clipped areas.
@Suite struct CommittedGeometryTests {
    @Test(arguments: ParityCase.osm2streets)
    func committedGeometry(_ c: ParityCase) throws {
        let expectedURL = try #require(Fixtures.existing(c.folder.appendingPathComponent("geometry.json")))
        var streets = try StreetNetwork.fromOSM(c.xmlBytes(), clip: c.clipPoints(), config: MapConfig())
        streets.checkInvariants()
        streets.applyTransformationsWithInvariantChecks(Transformation.standardForClippedAreas())
        let actual = streets.toGeoJSON(.all)
        let expected = String(decoding: try Fixtures.data(expectedURL), as: UTF8.self)
        let comparison = GeoJSONComparison.compare(expected: expected, actual: actual)
        print("GEOMETRY \(c.name): \(comparison.featuresActual)/\(comparison.featuresExpected) features, "
              + (comparison.identicalText ? "identical" : (comparison.matches ? "equal within 1e-9" : "differs at \(comparison.firstDifference!)")))
        #expect(comparison.identicalText, "\(comparison.firstDifference ?? "")")
    }
}

extension ParityCase: CustomTestStringConvertible {
    var testDescription: String { name }
}
