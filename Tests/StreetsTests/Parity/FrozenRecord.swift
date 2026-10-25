/// The Rust's answers, stored: for each committed input, every distinct
/// result the Rust binary gave over its runs, each result being its four
/// GeoJSON outputs by their SHA-256, length and feature count
/// (`Fixtures/rust/<case>.json`). An output is equal to a stored one when
/// its text has the same digest and length: byte-identical, the bar of the
/// live tests. Written by `FreezeOracle` from a live binary.

import CryptoKit
import Foundation

struct OutputDigest: Codable, Hashable, Sendable {
    var sha256: String
    var bytes: Int
    var features: Int

    init(_ text: String) {
        let data = Data(text.utf8)
        sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        bytes = data.count
        features = text.components(separatedBy: "\"type\": \"Feature\"").count - 1
    }

    var summary: String { "\(features) features, \(bytes) bytes, sha256 \(sha256.prefix(16))" }
}

/// One result: the four outputs, in the order of `Oracle.outputs`.
typealias ResultDigest = [OutputDigest]

func digest(_ outputs: [String]) -> ResultDigest { outputs.map(OutputDigest.init) }

struct FrozenRecord: Codable {
    /// What answered: the binary's name and revision.
    var oracle = "osm2streets-cli, osm2streets fc119c4"
    /// The date of the runs.
    var frozen: String
    var rustRuns: Int
    /// For the synthetic ways: the tag sets the Rust panics on, left out of the input.
    var rustRejected: [Int]?
    /// Every distinct result of the Rust's runs, in the order first seen.
    var rustResults: [[String: OutputDigest]]

    var results: [ResultDigest] { rustResults.map { r in Oracle.outputs.map { r[$0]! } } }

    static func url(_ name: String) -> URL { Fixtures.url("rust/\(name).json") }

    static func load(_ name: String) throws -> FrozenRecord {
        try JSONDecoder().decode(FrozenRecord.self, from: Data(contentsOf: url(name)))
    }

    static func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: url(name).path) }

    func save(_ name: String) throws {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        let u = Self.url(name)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (e.encode(self) + Data("\n".utf8)).write(to: u)
    }

    init(rustRuns: Int, rustRejected: [Int]? = nil, results: [ResultDigest]) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        frozen = f.string(from: Date())
        self.rustRuns = rustRuns
        self.rustRejected = rustRejected
        rustResults = results.map { Dictionary(uniqueKeysWithValues: zip(Oracle.outputs, $0)) }
    }
}
