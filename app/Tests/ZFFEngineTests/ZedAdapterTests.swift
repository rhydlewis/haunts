import Testing
import Foundation
@testable import HauntsAdapters

// MARK: - Helpers

private func writeTempFile(_ content: String) throws -> (URL, () -> Void) {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ZedTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("settings.json")
    try content.data(using: .utf8)!.write(to: file, options: .atomic)
    return (file, { try? FileManager.default.removeItem(at: dir) })
}

// MARK: - editorName

struct ZedAdapterNameTests {
    @Test func editorNameIsZed() {
        #expect(ZedAdapter().editorName == "Zed")
    }
}

// MARK: - recentFolders — happy path

struct ZedAdapterParseTests {

    @Test func parsesRecentDirsArray() throws {
        let json = """
        {"recent_dirs": ["/tmp/proj-a", "/tmp/proj-b"]}
        """
        let (file, cleanup) = try writeTempFile(json)
        defer { cleanup() }

        let adapter = ZedAdapter(configURL: file)
        let urls = try adapter.recentFolders()

        let paths = urls.map(\.path)
        #expect(paths.contains("/tmp/proj-a"))
        #expect(paths.contains("/tmp/proj-b"))
        #expect(paths.count == 2)
    }

    @Test func expandsTildeInPaths() throws {
        let home = NSHomeDirectory()
        let json = """
        {"recent_dirs": ["~/myproject"]}
        """
        let (file, cleanup) = try writeTempFile(json)
        defer { cleanup() }

        let adapter = ZedAdapter(configURL: file)
        let urls = try adapter.recentFolders()

        #expect(urls.first?.path == home + "/myproject")
    }

    @Test func emptyRecentDirsReturnsEmpty() throws {
        let json = """
        {"recent_dirs": []}
        """
        let (file, cleanup) = try writeTempFile(json)
        defer { cleanup() }

        let adapter = ZedAdapter(configURL: file)
        let urls = try adapter.recentFolders()
        #expect(urls.isEmpty)
    }

    @Test func missingRecentDirsKeyReturnsEmpty() throws {
        let json = """
        {"theme": "dark", "font_size": 14}
        """
        let (file, cleanup) = try writeTempFile(json)
        defer { cleanup() }

        let adapter = ZedAdapter(configURL: file)
        let urls = try adapter.recentFolders()
        #expect(urls.isEmpty)
    }

    @Test func nullRecentDirsReturnsEmpty() throws {
        let json = """
        {"recent_dirs": null}
        """
        let (file, cleanup) = try writeTempFile(json)
        defer { cleanup() }

        let adapter = ZedAdapter(configURL: file)
        let urls = try adapter.recentFolders()
        #expect(urls.isEmpty)
    }
}

// MARK: - recentFolders — error resilience

struct ZedAdapterResilienceTests {

    @Test func missingFileReturnsEmpty() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ZedTests-absent-\(UUID().uuidString)")
        let file = dir.appendingPathComponent("settings.json")
        // Do NOT create the file
        let adapter = ZedAdapter(configURL: file)
        let urls = try adapter.recentFolders()
        #expect(urls.isEmpty, "Missing config must return [] without throwing")
    }

    @Test func malformedJSONReturnsEmpty() throws {
        let (file, cleanup) = try writeTempFile("this is not json }{")
        defer { cleanup() }

        let adapter = ZedAdapter(configURL: file)
        let urls = try adapter.recentFolders()
        #expect(urls.isEmpty, "Malformed JSON must return [] without throwing")
    }

    @Test func truncatedJSONReturnsEmpty() throws {
        let (file, cleanup) = try writeTempFile("{\"recent_dirs\": [\"/tmp")
        defer { cleanup() }

        let adapter = ZedAdapter(configURL: file)
        let urls = try adapter.recentFolders()
        #expect(urls.isEmpty, "Truncated JSON must return [] without throwing")
    }

    @Test func emptyFileReturnsEmpty() throws {
        let (file, cleanup) = try writeTempFile("")
        defer { cleanup() }

        let adapter = ZedAdapter(configURL: file)
        let urls = try adapter.recentFolders()
        #expect(urls.isEmpty, "Empty file must return [] without throwing")
    }

    @Test func binaryGarbageReturnsEmpty() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ZedTests-binary-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("settings.json")
        defer { try? FileManager.default.removeItem(at: dir) }

        let garbage = Data([0xFF, 0xFE, 0x00, 0x01])
        try garbage.write(to: file, options: .atomic)

        let adapter = ZedAdapter(configURL: file)
        let urls = try adapter.recentFolders()
        #expect(urls.isEmpty, "Binary data must return [] without throwing")
    }
}
