/// One OSM input of the parity tests and its clip: a folder holding
/// `input.osm` (or `input.osm.lzma`, or an Overpass `osm.json`) and, when
/// the input is clipped, `boundary.json` (or `clip.geojson`), the layout of
/// osm2streets's own test cases.
///
/// The committed cases: osm2streets's 29 XML test cases
/// (`Fixtures/osm2streets/`) and the Moscow data (`Fixtures/moscow/`). More
/// folders can be given to the live tests in `SWIFTSTREETS_EXTRA_CASES`,
/// separated by colons.

import Foundation
import StreetGeom

struct ParityCase: Sendable, CustomStringConvertible {
    /// The group and the folder's name, `osm2streets/taipei`: the name of its stored answers too.
    var name: String
    var folder: URL

    var description: String { name }

    static func cases(in group: String) -> [ParityCase] {
        let dir = Fixtures.url(group)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.sorted().compactMap { n in
            let c = ParityCase(name: "\(group)/\(n)", folder: dir.appendingPathComponent(n))
            return c.inputFile == nil ? nil : c
        }
    }

    static let osm2streets = cases(in: "osm2streets")
    static let moscow = cases(in: "moscow")

    static let extra: [ParityCase] = (ProcessInfo.processInfo.environment["SWIFTSTREETS_EXTRA_CASES"] ?? "")
        .split(separator: ":").map { path in
            let url = URL(fileURLWithPath: (String(path) as NSString).expandingTildeInPath)
            return ParityCase(name: "extra/\(url.lastPathComponent)", folder: url)
        }

    var inputFile: URL? {
        for n in ["input.osm", "input.osm.lzma", "osm.json"] {
            let u = folder.appendingPathComponent(n)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    var clipFile: URL? {
        for n in ["boundary.json", "clip.geojson", "streets/clip.geojson"] {
            let u = folder.appendingPathComponent(n)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    /// The OSM XML both sides read.
    func xmlBytes() throws -> [UInt8] {
        guard let input = inputFile else { throw CocoaError(.fileNoSuchFile) }
        if input.lastPathComponent == "osm.json" {
            return Array(try OverpassXML.convert(Data(contentsOf: input)).utf8)
        }
        return Array(try Fixtures.data(input))
    }

    /// The clip polygon as the Rust reads it.
    func clipPoints() throws -> [LonLat]? {
        try clipFile.map { url -> [LonLat] in
            let polygons = try LonLat.parseGeoJSONPolygons(String(contentsOf: url, encoding: .utf8))
            precondition(polygons.count == 1, "the clip GeoJSON must hold exactly one polygon")
            return polygons[0].0
        }
    }

    /// The input as a plain XML file for the Rust binary: the file itself when it is one.
    func xmlFile(_ bytes: [UInt8]) throws -> URL {
        if let input = inputFile, input.lastPathComponent == "input.osm" { return input }
        let out = Oracle.scratch.appendingPathComponent(name).appendingPathComponent("input.osm")
        try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(bytes).write(to: out)
        return out
    }
}
