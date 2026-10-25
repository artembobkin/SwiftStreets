/// Synthetic OSM files for checking Muv's lane reading against the Rust:
/// one way per tag set, each crossing the whole box so that clipping makes
/// both its ends map edges and nothing collapses, inside a box placed in a
/// country (the country picks the driving side and Muv's legal defaults).
/// Both the Rust binary and the port read the file; their outputs must be
/// identical, and when they are not, the lanes of the first way that
/// differs (and its tags) say where.

import Foundation
import StreetGeom
import Streets

struct SyntheticBox {
    var name: String
    var minLon, minLat, maxLon, maxLat: Double

    /// A small box around a point (narrow: each way's lane markings grow
    /// with its length, a few megabytes per kilometre).
    static func around(_ name: String, lon: Double, lat: Double) -> SyntheticBox {
        SyntheticBox(name: name, minLon: lon - 0.002, minLat: lat - 0.004, maxLon: lon + 0.002, maxLat: lat + 0.004)
    }
}

enum SyntheticWays {
    /// The OSM XML: three nodes per way across the box, then the ways.
    static func xml(_ tagSets: [[(String, String)]], in b: SyntheticBox) -> String {
        let n = tagSets.count
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<osm version=\"0.6\">\n"
        let width = b.maxLon - b.minLon, height = b.maxLat - b.minLat
        for k in 0..<n {
            let lat = b.minLat + height * Double(k + 1) / Double(n + 1)
            let lons = [b.minLon - width * 0.1, b.minLon + width * 0.5, b.maxLon + width * 0.1]
            for (j, lon) in lons.enumerated() {
                xml += "<node id=\"\(3 * k + j + 1)\" version=\"1\" lat=\"\(serdeJSONNumber(lat))\" lon=\"\(serdeJSONNumber(lon))\"/>\n"
            }
        }
        for (k, tags) in tagSets.enumerated() {
            xml += "<way id=\"\(k + 1)\" version=\"1\">"
            for j in 0..<3 { xml += "<nd ref=\"\(3 * k + j + 1)\"/>" }
            for (key, value) in tags { xml += "<tag k=\(xmlQuote(key)) v=\(xmlQuote(value))/>" }
            xml += "</way>\n"
        }
        return xml + "</osm>\n"
    }

    static func clip(_ b: SyntheticBox) -> String {
        let ring = [(b.minLon, b.minLat), (b.maxLon, b.minLat), (b.maxLon, b.maxLat), (b.minLon, b.maxLat), (b.minLon, b.minLat)]
            .map { "[\(serdeJSONNumber($0.0)), \(serdeJSONNumber($0.1))]" }.joined(separator: ", ")
        return "{\"type\": \"Feature\", \"properties\": {}, \"geometry\": {\"type\": \"Polygon\", \"coordinates\": [[\(ring)]]}}"
    }

    struct Result {
        var outputsIdentical: [String: Bool] = [:]
        var lanes = 0
        /// The first ways whose lanes differ: their tags and the two lanes.
        var firstDifference: String?
        var differingWays = 0
        var allIdentical: Bool { outputsIdentical.values.allSatisfy { $0 } }
    }

    /// The port's four outputs over the tag sets in the box, in the order of `Oracle.outputs`.
    static func portOutputs(_ tagSets: [[(String, String)]], in box: SyntheticBox) throws -> [String] {
        let clipPts = try LonLat.parseGeoJSONPolygons(clip(box))[0].0
        var streets = try StreetNetwork.fromOSM(Array(xml(tagSets, in: box).utf8), clip: clipPts,
                                                config: PortResults.parityConfig())
        streets.applyTransformations(Transformation.standardForClippedAreas())
        return [streets.toGeoJSON(.all), streets.toLanePolygonsGeoJSON(.all),
                try streets.toLaneMarkingsGeoJSON(.all), streets.toIntersectionMarkingsGeoJSON(.all)]
    }

    /// The Rust's four outputs over the tag sets in the box, in the order of `Oracle.outputs`.
    static func rustOutputs(_ tagSets: [[(String, String)]], in box: SyntheticBox, work: URL) throws -> [String] {
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let osm = work.appendingPathComponent("ways.osm")
        let clipURL = work.appendingPathComponent("clip.geojson")
        try xml(tagSets, in: box).write(to: osm, atomically: true, encoding: .utf8)
        try clip(box).write(to: clipURL, atomically: true, encoding: .utf8)
        let out = try Oracle.run(input: osm, clip: clipURL, out: work.appendingPathComponent("rust"))
        return Oracle.outputs.map { out[$0]! }
    }

    /// Runs the Rust and the port over the tag sets in the box.
    static func compare(_ tagSets: [[(String, String)]], in box: SyntheticBox, work: URL) throws -> Result {
        let expected = try rustOutputs(tagSets, in: box, work: work)
        let actual = try portOutputs(tagSets, in: box)
        let swiftDir = work.appendingPathComponent("swift")
        try FileManager.default.createDirectory(at: swiftDir, withIntermediateDirectories: true)
        for (k, text) in zip(Oracle.outputs, actual) {
            try text.write(to: swiftDir.appendingPathComponent("\(k).geojson"), atomically: true, encoding: .utf8)
        }
        return try compare(tagSets, expected: expected, actual: actual)
    }

    /// The two sides' outputs compared, and the first ways whose lanes differ.
    static func compare(_ tagSets: [[(String, String)]], expected: [String], actual: [String]) throws -> Result {
        var result = Result()
        for (k, (x, y)) in zip(Oracle.outputs, zip(expected, actual)) { result.outputsIdentical[k] = x == y }
        let e = try lanesByWay(expected[0], expected[1])
        let a = try lanesByWay(actual[0], actual[1])
        result.lanes = e.values.map(\.count).reduce(0, +)
        var report: [String] = []
        for (k, tags) in tagSets.enumerated() {
            let way = Int64(k + 1)
            let x = e[way] ?? [], y = a[way] ?? []
            let tagText = tags.map { "\($0.0)=\($0.1)" }.joined(separator: " ")
            if x.count != y.count {
                result.differingWays += 1
                if report.count < 8 { report.append("way \(way) [\(tagText)]: \(x.count) lanes expected, \(y.count) actual") }
            } else if let i = x.indices.first(where: { x[$0] != y[$0] }) {
                result.differingWays += 1
                if report.count < 8 { report.append("way \(way) [\(tagText)], lane \(i): \(lineDiff(x[i], y[i]))") }
            }
        }
        if !report.isEmpty { result.firstDifference = "\(result.differingWays) ways differ:\n" + report.joined(separator: "\n") }
        return result
    }

    /// The first lines where two texts differ, with a little context.
    static func lineDiff(_ e: String, _ a: String) -> String {
        let x = e.split(separator: "\n", omittingEmptySubsequences: false)
        let y = a.split(separator: "\n", omittingEmptySubsequences: false)
        guard let i = (0..<max(x.count, y.count)).first(where: { $0 >= x.count || $0 >= y.count || x[$0] != y[$0] }) else {
            return "identical"
        }
        let lo = max(0, i - 4)
        let ex = x[lo..<min(x.count, i + 3)].joined(separator: "\n")
        let ac = y[lo..<min(y.count, i + 3)].joined(separator: "\n")
        return "at line \(i)\n--- expected\n\(ex)\n--- actual\n\(ac)"
    }

    /// The indices of the tag sets the Rust fails on, each tried alone.
    static func rustRejected(_ tagSets: [[(String, String)]], in box: SyntheticBox, work: URL) throws -> Set<Int> {
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let clipURL = work.appendingPathComponent("clip.geojson")
        try clip(box).write(to: clipURL, atomically: true, encoding: .utf8)
        func fails(_ sets: [[(String, String)]]) throws -> Bool {
            let osm = work.appendingPathComponent("ways.osm")
            try xml(sets, in: box).write(to: osm, atomically: true, encoding: .utf8)
            do {
                _ = try Oracle.run(input: osm, clip: clipURL, out: work.appendingPathComponent("rust"))
                return false
            } catch OracleError.failed {
                return true
            }
        }
        var rejected = Set<Int>()
        for (k, set) in tagSets.enumerated() where try fails([set]) { rejected.insert(k) }
        return rejected
    }

    /// Each way's lane features (without their geometry), from the road's way.
    static func lanesByWay(_ plain: String, _ lanes: String) throws -> [Int64: [String]] {
        var wayOfRoad: [String: Int64] = [:]
        for f in try JSONValue.parse(plain)["features"]!.arrayValue! {
            let p = f["properties"]!
            guard p["type"]?.stringValue == "road", case .array(let ids) = p["osm_way_ids"]! else { continue }
            if case .int(let w) = ids[0] { wayOfRoad[p["id"]!.prettyString()] = w }
            if case .uint(let w) = ids[0] { wayOfRoad[p["id"]!.prettyString()] = Int64(w) }
        }
        var res: [Int64: [String]] = [:]
        for f in try JSONValue.parse(lanes)["features"]!.arrayValue! {
            let p = f["properties"]!
            guard let way = wayOfRoad[p["road"]!.prettyString()] else { continue }
            res[way, default: []].append(p.prettyString())
        }
        return res
    }
}

func xmlQuote(_ s: String) -> String {
    "\"" + s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;") + "\""
}
