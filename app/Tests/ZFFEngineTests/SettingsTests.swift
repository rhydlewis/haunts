import Testing
import Foundation
import AppKit
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

// MARK: - Session-4 settings (ranking / appearance / launch / refresh / terminal)

@Suite("Session4SettingsTests", .serialized)
struct Session4SettingsTests {

    private func clearKeys() {
        for key in [
            "haunts.rankingMode", "haunts.subfolderFrecency", "haunts.minVisitCount",
            "haunts.learnFromNavigation", "haunts.appearance", "haunts.launchAtLogin",
            "haunts.refreshIntervalMinutes", "haunts.terminalTarget",
        ] { UserDefaults.standard.removeObject(forKey: key) }
    }

    @Test func rankingModeDefaultsToBalanced() {
        clearKeys()
        #expect(Settings.rankingMode == "balanced")
    }

    @Test func rankingModeRoundTrips() {
        clearKeys()
        Settings.rankingMode = "frequent"
        #expect(Settings.rankingMode == "frequent")
        clearKeys()
    }

    @Test func subfolderFrecencyDefaultsOff() {
        clearKeys()
        #expect(Settings.subfolderFrecency == false)
    }

    @Test func subfolderFrecencyRoundTrips() {
        clearKeys()
        Settings.subfolderFrecency = true
        #expect(Settings.subfolderFrecency == true)
        clearKeys()
    }

    @Test func minVisitCountDefaultsToThree() {
        clearKeys()
        #expect(Settings.minVisitCount == 3)
    }

    @Test func minVisitCountRoundTrips() {
        clearKeys()
        Settings.minVisitCount = 7
        #expect(Settings.minVisitCount == 7)
        clearKeys()
    }

    @Test func learnFromNavigationDefaultsOn() {
        clearKeys()
        #expect(Settings.learnFromNavigation == true)
    }

    @Test func learnFromNavigationRoundTrips() {
        clearKeys()
        Settings.learnFromNavigation = false
        #expect(Settings.learnFromNavigation == false)
        clearKeys()
    }

    @Test func appearanceDefaultsToSystem() {
        clearKeys()
        #expect(Settings.appearance == "system")
    }

    @Test func appearanceRoundTrips() {
        clearKeys()
        Settings.appearance = "dark"
        #expect(Settings.appearance == "dark")
        clearKeys()
    }

    @Test func launchAtLoginDefaultsOff() {
        clearKeys()
        #expect(Settings.launchAtLogin == false)
    }

    @Test func launchAtLoginRoundTrips() {
        clearKeys()
        Settings.launchAtLogin = true
        #expect(Settings.launchAtLogin == true)
        clearKeys()
    }

    @Test func refreshIntervalDefaultsTo15() {
        clearKeys()
        #expect(Settings.refreshIntervalMinutes == 15)
    }

    @Test func refreshIntervalRoundTripsIncludingManualZero() {
        clearKeys()
        Settings.refreshIntervalMinutes = 60
        #expect(Settings.refreshIntervalMinutes == 60)
        Settings.refreshIntervalMinutes = 0   // "Manually"
        #expect(Settings.refreshIntervalMinutes == 0)
        clearKeys()
    }

    @Test func terminalDefaultsToTerminal() {
        clearKeys()
        #expect(Settings.terminalTarget == "Terminal")
    }

    @Test func terminalRoundTrips() {
        clearKeys()
        Settings.terminalTarget = "iTerm"
        #expect(Settings.terminalTarget == "iTerm")
        clearKeys()
    }

    @Test func detectInstalledTerminalsNeverEmpty() {
        // Machine-dependent, but must always include at least the built-in Terminal.
        let found = Settings.detectInstalledTerminals()
        #expect(found.contains("Terminal"))
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

    // Every detected editor must be a known one AND actually resolvable on this
    // machine — via Launch Services (which finds ~/Applications, JetBrains Toolbox,
    // etc.) or, as a fallback, a /Applications bundle. This is the real detection
    // criterion; it deliberately does NOT require the app to live in /Applications.
    @Test func detectOnlyReturnsResolvableKnownEditors() {
        let detected = Settings.detectInstalledEditors()
        let fm = FileManager.default
        let knownFallbackNames: [String: [String]] = [
            "dev.zed.Zed":           ["Zed"],
            "com.apple.dt.Xcode":    ["Xcode"],
            "com.jetbrains.pycharm": ["PyCharm CE", "PyCharm"],
            "com.microsoft.VSCode":  ["Visual Studio Code"],
            "com.panic.Nova":        ["Nova"],
            "com.sublimetext.4":     ["Sublime Text"],
        ]
        for editor in detected {
            #expect(knownFallbackNames[editor.bundleID] != nil,
                    "Detected unknown bundleID \(editor.bundleID)")
            let resolvable = NSWorkspace.shared
                .urlForApplication(withBundleIdentifier: editor.bundleID) != nil
            let inAppsFolder = (knownFallbackNames[editor.bundleID] ?? [])
                .contains { fm.fileExists(atPath: "/Applications/\($0).app") }
            #expect(resolvable || inAppsFolder,
                    "Detected \(editor.name) but it resolves via neither Launch Services nor /Applications")
        }
    }
}

// MARK: - Hotkey defaults

@Suite("HotkeyDefaultTests", .serialized)
struct HotkeyDefaultTests {

    private func clearKeys() {
        UserDefaults.standard.removeObject(forKey: "haunts.hotkeyKeyCode")
        UserDefaults.standard.removeObject(forKey: "haunts.hotkeyModifiers")
    }

    // Carbon: kVK_Space = 49, optionKey = 2048. The default summon chord is
    // ⌥Space — clear of macOS symbolic hotkeys (⌘Space Spotlight, ⌃Space /
    // ⌃⌥Space input source, ⌃⌘Space emoji) and of Finder's ⌘⇧H Home.
    @Test func defaultChordIsOptionSpace() {
        #expect(Settings.defaultHotkeyKeyCode == 49)
        #expect(Settings.defaultHotkeyModifiers == 2048)
    }

    @Test func freshInstallResolvesToOptionSpace() {
        clearKeys()
        #expect(Settings.hotkeyKeyCode == 49)
        #expect(Settings.hotkeyModifiers == 2048)
        clearKeys()
    }

    // A user who rebound keeps their chord — the stored value wins over the default.
    @Test func storedOverrideWinsOverDefault() {
        clearKeys()
        Settings.hotkeyKeyCode = 49
        Settings.hotkeyModifiers = 256 + 4096   // ⌃⌘
        #expect(Settings.hotkeyModifiers == 4352)
        clearKeys()
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
