import Foundation

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

    // Default: Space (keyCode 49) + ⌃⌘ (cmdKey | controlKey = 256 | 4096 = 4352)
    public static let defaultHotkeyKeyCode: UInt32 = 49
    public static let defaultHotkeyModifiers: UInt32 = 256 + 4096

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

    public static func detectInstalledEditors() -> [EditorTarget] {
        let fm = FileManager.default
        var seen: Set<String> = []
        var result: [EditorTarget] = []
        for editor in knownEditors {
            guard !seen.contains(editor.bundleID) else { continue }
            let found = editor.appNames.contains { appName in
                fm.fileExists(atPath: "/Applications/\(appName).app")
            }
            if found {
                seen.insert(editor.bundleID)
                result.append(EditorTarget(name: editor.name, bundleID: editor.bundleID))
            }
        }
        return result
    }
}
