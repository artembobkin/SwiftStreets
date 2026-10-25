/// The Rust osm2streets the parity tests compare against, when it is at
/// hand: a command line build of osm2streets at revision fc119c4 (with
/// streets_reader and osm2lanes of the same revision), named by the
/// environment variable `OSM2STREETS_CLI`. It is run as
/// `<binary> <input.osm> <clip.geojson | -> <out dir>` and writes
/// `plain.geojson`, `lanes.geojson`, `lane_markings.geojson` and
/// `intersection_markings.geojson`, with inferred sidewalks and kerbs and
/// the standard transformations for clipped areas. The live tests skip
/// when the variable is unset. Without it, the stored answers of the same
/// binary (`Fixtures/rust/`) stand in for it.

import Foundation

enum Oracle {
    /// The binary named by `OSM2STREETS_CLI`, if it is set.
    static let binary: URL? = ProcessInfo.processInfo.environment["OSM2STREETS_CLI"]
        .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }

    static var available: Bool { binary.map { FileManager.default.isExecutableFile(atPath: $0.path) } ?? false }

    /// Where the live tests write the inputs they hand to the binary, and both sides' outputs.
    static let scratch = Fixtures.scratch.appendingPathComponent("parity")

    static let outputs = ["plain", "lanes", "lane_markings", "intersection_markings"]

    /// Runs the binary: `<input> <clip | -> <out dir>`. Returns its outputs by name.
    static func run(input: URL, clip: URL?, out: URL) throws -> [String: String] {
        guard let binary else { throw OracleError.failed("OSM2STREETS_CLI is not set") }
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = binary
        p.arguments = [input.path, clip?.path ?? "-", out.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        let log = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw OracleError.failed(String(decoding: log.suffix(2000), as: UTF8.self))
        }
        var result: [String: String] = [:]
        for name in outputs {
            result[name] = try String(contentsOf: out.appendingPathComponent("\(name).geojson"), encoding: .utf8)
        }
        return result
    }
}

enum OracleError: Error, CustomStringConvertible {
    case failed(String)
    var description: String {
        switch self {
        case .failed(let log): return "osm2streets-cli failed: \(log)"
        }
    }
}
