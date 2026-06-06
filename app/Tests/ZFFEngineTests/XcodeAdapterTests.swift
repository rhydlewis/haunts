import Testing
import Foundation
@testable import HauntsAdapters

// MARK: - editorName

struct XcodeAdapterNameTests {
    @Test func editorNameIsXcode() {
        #expect(XcodeAdapter().editorName == "Xcode")
    }
}

// MARK: - recentFolders — error resilience

struct XcodeAdapterResilienceTests {

    @Test func missingPlistReturnsEmpty() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("XcodeTests-absent-\(UUID().uuidString)")
        let plist = dir.appendingPathComponent("IDERecentDocuments.plist")
        // Do NOT create the file — simulates Xcode not installed
        let adapter = XcodeAdapter(plistURL: plist)
        let urls = try adapter.recentFolders()
        #expect(urls.isEmpty, "Missing plist must return [] without throwing")
    }

    @Test func malformedPlistReturnsEmpty() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("XcodeTests-malformed-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let plist = dir.appendingPathComponent("IDERecentDocuments.plist")
        defer { try? FileManager.default.removeItem(at: dir) }

        try "this is not a plist".data(using: .utf8)!.write(to: plist, options: .atomic)

        let adapter = XcodeAdapter(plistURL: plist)
        let urls = try adapter.recentFolders()
        #expect(urls.isEmpty, "Malformed plist must return [] without throwing")
    }

    @Test func emptyArrayPlistReturnsEmpty() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("XcodeTests-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let plist = dir.appendingPathComponent("IDERecentDocuments.plist")
        defer { try? FileManager.default.removeItem(at: dir) }

        // Valid plist, but array is empty
        let emptyArray: [[String: Any]] = []
        let data = try PropertyListSerialization.data(fromPropertyList: emptyArray, format: .xml, options: 0)
        try data.write(to: plist, options: .atomic)

        let adapter = XcodeAdapter(plistURL: plist)
        let urls = try adapter.recentFolders()
        #expect(urls.isEmpty)
    }

    @Test func plistWithPathKeyReturnsExistingDirectories() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("XcodeTests-path-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let plist = dir.appendingPathComponent("IDERecentDocuments.plist")
        defer { try? FileManager.default.removeItem(at: dir) }

        // Create a real directory to reference
        let projectDir = dir.appendingPathComponent("MyProject", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let entries: [[String: Any]] = [
            ["Path": projectDir.path]
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: entries, format: .xml, options: 0)
        try data.write(to: plist, options: .atomic)

        let adapter = XcodeAdapter(plistURL: plist)
        let urls = try adapter.recentFolders()

        let paths = urls.map(\.path)
        #expect(paths.contains(projectDir.path), "Existing directory from 'Path' key must be returned")
    }

    @Test func plistWithStalePathReturnsEmpty() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("XcodeTests-stale-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let plist = dir.appendingPathComponent("IDERecentDocuments.plist")
        defer { try? FileManager.default.removeItem(at: dir) }

        // Path that does not exist on disk
        let entries: [[String: Any]] = [
            ["Path": "/nonexistent/path/that/does/not/exist"]
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: entries, format: .xml, options: 0)
        try data.write(to: plist, options: .atomic)

        let adapter = XcodeAdapter(plistURL: plist)
        let urls = try adapter.recentFolders()
        #expect(urls.isEmpty, "Stale paths must be silently dropped")
    }
}
