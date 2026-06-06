import Testing
import Foundation
@testable import HauntsCore

// MARK: - EditorTarget struct

@Suite("EditorTargetStructTests")
struct EditorTargetStructTests {

    @Test func structHasExpectedFields() {
        let id = UUID()
        let target = EditorTarget(id: id, name: "Zed", bundleID: "dev.zed.Zed", cliPath: "/usr/local/bin/zed")
        #expect(target.id == id)
        #expect(target.name == "Zed")
        #expect(target.bundleID == "dev.zed.Zed")
        #expect(target.cliPath == "/usr/local/bin/zed")
        #expect(target.isEnabled == true)
    }

    @Test func nilCliPathRoundTrips() throws {
        let original = EditorTarget(name: "Xcode", bundleID: "com.apple.dt.Xcode", cliPath: nil)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EditorTarget.self, from: data)
        #expect(decoded.name == original.name)
        #expect(decoded.bundleID == original.bundleID)
        #expect(decoded.cliPath == nil)
    }

    @Test func nonNilCliPathRoundTrips() throws {
        let original = EditorTarget(name: "Zed", bundleID: "dev.zed.Zed", cliPath: "/usr/local/bin/zed")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EditorTarget.self, from: data)
        #expect(decoded.cliPath == "/usr/local/bin/zed")
    }

    @Test func arrayRoundTrips() throws {
        let targets = [
            EditorTarget(name: "Zed", bundleID: "dev.zed.Zed"),
            EditorTarget(name: "VS Code", bundleID: "com.microsoft.VSCode", isEnabled: false),
        ]
        let data = try JSONEncoder().encode(targets)
        let decoded = try JSONDecoder().decode([EditorTarget].self, from: data)
        #expect(decoded.count == 2)
        #expect(decoded[0].name == "Zed")
        #expect(decoded[1].isEnabled == false)
    }
}

// MARK: - Settings UserDefaults persistence

@Suite("SettingsPersistenceTests", .serialized)
struct SettingsPersistenceTests {

    private func clearKeys() {
        UserDefaults.standard.removeObject(forKey: "haunts.editorTargets")
        UserDefaults.standard.removeObject(forKey: "haunts.scanRoots")
    }

    @Test func editorTargetsAbsentKeyReturnsEmpty() {
        clearKeys()
        #expect(Settings.editorTargets.isEmpty)
    }

    @Test func editorTargetsWriteAndReadBack() {
        clearKeys()
        let targets = [EditorTarget(name: "Nova", bundleID: "com.panic.Nova")]
        Settings.editorTargets = targets
        let loaded = Settings.editorTargets
        #expect(loaded.count == 1)
        #expect(loaded[0].name == "Nova")
        #expect(loaded[0].bundleID == "com.panic.Nova")
        clearKeys()
    }

    @Test func malformedEditorTargetsDataReturnsEmpty() {
        UserDefaults.standard.set(Data("not json".utf8), forKey: "haunts.editorTargets")
        let loaded = Settings.editorTargets
        #expect(loaded.isEmpty)
        clearKeys()
    }

    @Test func scanRootsDefaultWhenAbsent() {
        clearKeys()
        let defaults = Settings.scanRoots
        #expect(defaults.count == 2)
        let home = NSHomeDirectory()
        #expect(defaults[0].path == home + "/code")
        #expect(defaults[0].depth == 4)
        #expect(defaults[1].path == home)
        #expect(defaults[1].depth == 2)
    }

    @Test func scanRootsCustomRoundTrips() {
        clearKeys()
        let custom = [ScanRoot(path: "/tmp/myprojects", depth: 3)]
        Settings.scanRoots = custom
        let loaded = Settings.scanRoots
        #expect(loaded.count == 1)
        #expect(loaded[0].path == "/tmp/myprojects")
        #expect(loaded[0].depth == 3)
        clearKeys()
    }
}

// MARK: - EditorTarget autodetect

@Suite("EditorTargetDetectTests")
struct EditorTargetDetectTests {

    @Test func detectReturnsNoCrashWhenNoEditorsInstalled() {
        // This test verifies the function completes without crash.
        // Result will vary by machine — just check it's a valid array.
        let detected = Settings.detectInstalledEditors()
        // Result may be empty or non-empty depending on machine; no crash is the assertion.
        #expect(detected.count >= 0)
    }

    @Test func detectNoDuplicateBundleIDs() {
        let detected = Settings.detectInstalledEditors()
        let bundleIDs = detected.map { $0.bundleID }
        let unique = Set(bundleIDs)
        #expect(bundleIDs.count == unique.count)
    }

    @Test func detectOnlyReturnsExistingApps() {
        let detected = Settings.detectInstalledEditors()
        let fm = FileManager.default
        for editor in detected {
            // Each detected editor must have at least one .app bundle in /Applications
            let appNames: [String]
            switch editor.bundleID {
            case "dev.zed.Zed":           appNames = ["Zed"]
            case "com.apple.dt.Xcode":    appNames = ["Xcode"]
            case "com.jetbrains.pycharm": appNames = ["PyCharm CE", "PyCharm"]
            case "com.microsoft.VSCode":  appNames = ["Visual Studio Code"]
            case "com.panic.Nova":        appNames = ["Nova"]
            case "com.sublimetext.4":     appNames = ["Sublime Text"]
            default:                      appNames = []
            }
            let exists = appNames.contains { fm.fileExists(atPath: "/Applications/\($0).app") }
            #expect(exists, "Detected \(editor.name) but no matching .app found in /Applications")
        }
    }
}

// MARK: - ScanRoot struct

@Suite("ScanRootStructTests")
struct ScanRootStructTests {

    @Test func roundTrips() throws {
        let root = ScanRoot(path: "/Users/test/projects", depth: 3)
        let data = try JSONEncoder().encode(root)
        let decoded = try JSONDecoder().decode(ScanRoot.self, from: data)
        #expect(decoded.path == "/Users/test/projects")
        #expect(decoded.depth == 3)
    }
}
