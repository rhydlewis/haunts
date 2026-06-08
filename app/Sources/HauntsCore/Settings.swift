import Foundation
#if canImport(AppKit)
import AppKit
#endif

// MARK: - EditorTarget

public struct EditorTarget: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var bundleID: String
    public var cliPath: String?
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        bundleID: String,
        cliPath: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.bundleID = bundleID
        self.cliPath = cliPath
        self.isEnabled = isEnabled
    }
}

// MARK: - ScanRoot

public struct ScanRoot: Codable, Sendable, Equatable {
    public var path: String
    public var depth: Int

    public init(path: String, depth: Int) {
        self.path = path
        self.depth = depth
    }
}

// MARK: - Settings

public struct Settings {

    // MARK: Hotkey

    // Default: Space (keyCode 49) + ⌥ (optionKey = 2048).
    // ⌥Space is the conventional launcher chord and is clear of macOS symbolic
    // hotkeys (⌘Space Spotlight, ⌃Space / ⌃⌥Space input source, ⌃⌘Space emoji)
    // and of Finder's ⌘⇧H Home. Earlier default was ⌃⌘Space (4352), which
    // collided with the system Emoji & Symbols viewer. Only fresh/unmodified
    // installs flip — a user who rebound keeps their stored chord.
    public static let defaultHotkeyKeyCode: UInt32 = 49
    public static let defaultHotkeyModifiers: UInt32 = 2048

    public static var hotkeyKeyCode: UInt32 {
        get {
            let raw = UserDefaults.standard.integer(forKey: "haunts.hotkeyKeyCode")
            return raw == 0 ? defaultHotkeyKeyCode : UInt32(raw)
        }
        set { UserDefaults.standard.set(Int(newValue), forKey: "haunts.hotkeyKeyCode") }
    }

    public static var hotkeyModifiers: UInt32 {
        get {
            let raw = UserDefaults.standard.integer(forKey: "haunts.hotkeyModifiers")
            return raw == 0 ? defaultHotkeyModifiers : UInt32(raw)
        }
        set { UserDefaults.standard.set(Int(newValue), forKey: "haunts.hotkeyModifiers") }
    }

    // MARK: Ranking

    /// Raw ranking-mode identifier. Kept as a String so `Settings` stays
    /// Foundation-only; `AppState` maps it to `ZFFEngine.RankingMode`.
    /// Valid values: "balanced" (default) / "frequent".
    public static let defaultRankingMode = "balanced"
    public static var rankingMode: String {
        get { UserDefaults.standard.string(forKey: "haunts.rankingMode") ?? defaultRankingMode }
        set { UserDefaults.standard.set(newValue, forKey: "haunts.rankingMode") }
    }

    /// Keep a frequently-visited subfolder as its own result instead of
    /// collapsing it into the git root. Default off.
    public static var subfolderFrecency: Bool {
        get { UserDefaults.standard.bool(forKey: "haunts.subfolderFrecency") }
        set { UserDefaults.standard.set(newValue, forKey: "haunts.subfolderFrecency") }
    }

    /// Minimum visits before a subfolder is kept (used with `subfolderFrecency`).
    public static let defaultMinVisitCount = 3
    public static var minVisitCount: Int {
        get {
            let raw = UserDefaults.standard.integer(forKey: "haunts.minVisitCount")
            return raw == 0 ? defaultMinVisitCount : raw
        }
        set { UserDefaults.standard.set(newValue, forKey: "haunts.minVisitCount") }
    }

    /// Persisted only this session — the live Finder tracker is Session 5.
    /// Defaults on (matches the mockup).
    public static var learnFromNavigation: Bool {
        get { boolOrDefault("haunts.learnFromNavigation", default: true) }
        set { UserDefaults.standard.set(newValue, forKey: "haunts.learnFromNavigation") }
    }

    // MARK: Appearance

    /// "system" (default) / "light" / "dark". Drives `NSApp.appearance`.
    public static let defaultAppearance = "system"
    public static var appearance: String {
        get { UserDefaults.standard.string(forKey: "haunts.appearance") ?? defaultAppearance }
        set { UserDefaults.standard.set(newValue, forKey: "haunts.appearance") }
    }

    // MARK: Launch at login

    /// Persisted preference. Actual `SMAppService` registration only takes
    /// effect from a signed `.app` bundle, not the SwiftPM debug binary.
    public static var launchAtLogin: Bool {
        get { UserDefaults.standard.bool(forKey: "haunts.launchAtLogin") }
        set { UserDefaults.standard.set(newValue, forKey: "haunts.launchAtLogin") }
    }

    /// One-shot gate for the first-run "Open at login?" prompt. Flipped true the
    /// first time the prompt is shown so it never reappears (bead 2iw). Default
    /// false for a fresh install.
    public static var hasSeenLaunchPrompt: Bool {
        get { UserDefaults.standard.bool(forKey: "haunts.hasSeenLaunchPrompt") }
        set { UserDefaults.standard.set(newValue, forKey: "haunts.hasSeenLaunchPrompt") }
    }

    // MARK: Refresh interval

    /// Index refresh interval in minutes. 0 means "Manually". Default 15.
    public static let defaultRefreshInterval = 15
    public static var refreshIntervalMinutes: Int {
        get {
            guard UserDefaults.standard.object(forKey: "haunts.refreshIntervalMinutes") != nil else {
                return defaultRefreshInterval
            }
            return UserDefaults.standard.integer(forKey: "haunts.refreshIntervalMinutes")
        }
        set { UserDefaults.standard.set(newValue, forKey: "haunts.refreshIntervalMinutes") }
    }

    // MARK: Terminal target

    /// App name used for the ⌃↩ "open in terminal" verb. Default "Terminal".
    public static let defaultTerminal = "Terminal"
    public static var terminalTarget: String {
        get { UserDefaults.standard.string(forKey: "haunts.terminalTarget") ?? defaultTerminal }
        set { UserDefaults.standard.set(newValue, forKey: "haunts.terminalTarget") }
    }

    /// Terminal apps offered in the picker (only those installed are shown).
    public static let knownTerminals = ["Terminal", "iTerm", "Warp", "Ghostty"]

    public static func detectInstalledTerminals() -> [String] {
        let fm = FileManager.default
        let appName: [String: String] = [
            "Terminal": "Terminal", "iTerm": "iTerm", "Warp": "Warp", "Ghostty": "Ghostty",
        ]
        var found = knownTerminals.filter { fm.fileExists(atPath: "/Applications/\(appName[$0] ?? $0).app") }
        // /System path for the built-in Terminal.app
        if !found.contains("Terminal"),
           fm.fileExists(atPath: "/System/Applications/Utilities/Terminal.app") {
            found.insert("Terminal", at: 0)
        }
        return found.isEmpty ? ["Terminal"] : found
    }

    // MARK: Analytics

    /// Last app version seen on launch. Drives the install-vs-upgrade decision
    /// behind the anonymous GoatCounter count (see `Analytics`); purely local
    /// bookkeeping that never leaves the Mac.
    public static var lastSeenVersion: String? {
        get { UserDefaults.standard.string(forKey: "haunts.lastSeenVersion") }
        set { UserDefaults.standard.set(newValue, forKey: "haunts.lastSeenVersion") }
    }

    /// Timestamp of the very first launch. Stamped exactly once (by
    /// `Analytics.reportLaunch`) and never overwritten — the Usage tab reads it for
    /// "jumps since <date>". `nil` until first stamped. Local-only; never sent.
    public static var firstLaunchDate: Date? {
        get { UserDefaults.standard.object(forKey: "haunts.firstLaunchDate") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "haunts.firstLaunchDate") }
    }

    // MARK: - Helpers

    private static func boolOrDefault(_ key: String, default def: Bool) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return def }
        return UserDefaults.standard.bool(forKey: key)
    }

    // MARK: Editor targets

    public static var editorTargets: [EditorTarget] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "haunts.editorTargets") else { return [] }
            return (try? JSONDecoder().decode([EditorTarget].self, from: data)) ?? []
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: "haunts.editorTargets")
        }
    }

    /// Returns stored editors; if none stored, auto-detects and persists the results.
    public static func editorTargetsOrDefault() -> [EditorTarget] {
        let stored = editorTargets
        if !stored.isEmpty { return stored }
        let detected = detectInstalledEditors()
        if !detected.isEmpty {
            editorTargets = detected
        }
        return detected
    }

    // MARK: Scan roots

    public static var scanRoots: [ScanRoot] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "haunts.scanRoots") else {
                return defaultScanRoots()
            }
            return (try? JSONDecoder().decode([ScanRoot].self, from: data)) ?? defaultScanRoots()
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: "haunts.scanRoots")
        }
    }

    public static func defaultScanRoots() -> [ScanRoot] {
        let home = NSHomeDirectory()
        return [
            ScanRoot(path: home + "/code", depth: 4),
            ScanRoot(path: home, depth: 2),
        ]
    }

    // MARK: - Editor detection

    private struct KnownEditor {
        let name: String
        let bundleID: String
        let appNames: [String]
    }

    private static let knownEditors: [KnownEditor] = [
        KnownEditor(name: "Zed",          bundleID: "dev.zed.Zed",             appNames: ["Zed"]),
        KnownEditor(name: "Xcode",        bundleID: "com.apple.dt.Xcode",      appNames: ["Xcode"]),
        KnownEditor(name: "PyCharm",      bundleID: "com.jetbrains.pycharm",   appNames: ["PyCharm CE", "PyCharm"]),
        KnownEditor(name: "VS Code",      bundleID: "com.microsoft.VSCode",    appNames: ["Visual Studio Code"]),
        KnownEditor(name: "Nova",         bundleID: "com.panic.Nova",          appNames: ["Nova"]),
        KnownEditor(name: "Sublime Text", bundleID: "com.sublimetext.4",       appNames: ["Sublime Text"]),
    ]

    /// Resolve a known editor's install location regardless of where it lives.
    /// Launch Services (`NSWorkspace.urlForApplication(withBundleIdentifier:)`)
    /// finds apps in /Applications, ~/Applications (JetBrains Toolbox), etc. The
    /// `/Applications/<name>.app` check is kept only as a fallback for the rare
    /// case where Launch Services hasn't registered the bundle.
    private static func isEditorInstalled(_ editor: KnownEditor) -> Bool {
        #if canImport(AppKit)
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: editor.bundleID) != nil {
            return true
        }
        #endif
        let fm = FileManager.default
        return editor.appNames.contains { fm.fileExists(atPath: "/Applications/\($0).app") }
    }

    public static func detectInstalledEditors() -> [EditorTarget] {
        var seen: Set<String> = []
        var result: [EditorTarget] = []
        for editor in knownEditors {
            guard !seen.contains(editor.bundleID) else { continue }
            if isEditorInstalled(editor) {
                seen.insert(editor.bundleID)
                result.append(EditorTarget(name: editor.name, bundleID: editor.bundleID))
            }
        }
        return result
    }
}
