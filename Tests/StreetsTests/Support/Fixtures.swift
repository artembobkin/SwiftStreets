/// Where the committed test data lives (`Tests/StreetsTests/Fixtures/`,
/// left out of the target and read through `#filePath`), and how its
/// compressed files are read: `.lzma` files are LZMA (xz) streams, read
/// with Foundation's decompression (Apple platforms).

import Foundation

enum Fixtures {
    /// `Tests/StreetsTests/Fixtures`.
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")

    static func url(_ path: String) -> URL { root.appendingPathComponent(path) }

    /// The bytes of a fixture, decompressed when its name ends in `.lzma`.
    static func data(_ url: URL) throws -> Data {
        let raw = try Data(contentsOf: url)
        guard url.pathExtension == "lzma" else { return raw }
        return try (raw as NSData).decompressed(using: .lzma) as Data
    }

    /// The file itself, or its `.lzma` beside it, if either exists.
    static func existing(_ url: URL) -> URL? {
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let packed = url.appendingPathExtension("lzma")
        return FileManager.default.fileExists(atPath: packed.path) ? packed : nil
    }

    /// Writes data LZMA-compressed (used when freezing the oracle).
    static func writeCompressed(_ data: Data, to url: URL) throws {
        try (data as NSData).compressed(using: .lzma).write(to: url)
    }

    /// A folder for the files a test writes, under the system's temporary folder.
    static let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("SwiftStreetsTests")
}
