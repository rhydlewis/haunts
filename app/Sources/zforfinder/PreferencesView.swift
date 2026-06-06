import SwiftUI
import AppKit
import Carbon.HIToolbox
import HauntsCore

// MARK: - Theme

extension Color {
    /// Haunts ember accent ramp.
    static let ember     = Color(red: 0xE8 / 255, green: 0x73 / 255, blue: 0x2C / 255) // #E8732C
    static let emberGlow = Color(red: 0xFF / 255, green: 0xC9 / 255, blue: 0x8A / 255) // #FFC98A
    static let emberDeep = Color(red: 0xB8 / 255, green: 0x41 / 255, blue: 0x0F / 255) // #B8410F
}

/// Apply the persisted appearance preference to the whole app.
@MainActor func applyAppearance(_ raw: String) {
    switch raw {
    case "light": NSApp.appearance = NSAppearance(named: .aqua)
    case "dark":  NSApp.appearance = NSAppearance(named: .darkAqua)
    default:      NSApp.appearance = nil   // follow the system
    }
}

// MARK: - Model

/// Backs the Preferences window: mirrors `Settings`, persists on change, and
/// drives live side-effects (re-blend ranking, remap hotkey, switch appearance).
@MainActor
final class PreferencesModel: ObservableObject {
    weak var appState: AppState?

    // General
    @Published var hotkeyDisplay: String
    @Published var recording = false
    @Published var launchAtLogin: Bool { didSet { Settings.launchAtLogin = launchAtLogin; applyLaunchAtLogin() } }
    @Published var appearance: String { didSet { Settings.appearance = appearance; applyAppearance(appearance) } }
    @Published var refreshInterval: Int { didSet { Settings.refreshIntervalMinutes = refreshInterval } }

    // Ranking
    @Published var rankingMode: String { didSet { Settings.rankingMode = rankingMode; appState?.applyRankingSettings() } }
    @Published var learnFromNavigation: Bool { didSet { Settings.learnFromNavigation = learnFromNavigation } }
    @Published var subfolderFrecency: Bool { didSet { Settings.subfolderFrecency = subfolderFrecency; appState?.applyRankingSettings() } }
    @Published var minVisitCount: Int { didSet { Settings.minVisitCount = minVisitCount; appState?.applyRankingSettings() } }

    // Folders
    @Published var scanRoots: [ScanRoot] { didSet { Settings.scanRoots = scanRoots } }

    // Open With
    @Published var editorTargets: [EditorTarget] { didSet { Settings.editorTargets = editorTargets } }
    @Published var terminalTarget: String { didSet { Settings.terminalTarget = terminalTarget } }
    @Published var installedTerminals: [String]

    private var recordMonitor: Any?

    init(appState: AppState?) {
        self.appState = appState
        self.hotkeyDisplay = HotKeyUtils.displayString(keyCode: Settings.hotkeyKeyCode,
                                                       carbonModifiers: Settings.hotkeyModifiers)
        self.launchAtLogin = Settings.launchAtLogin
        self.appearance = Settings.appearance
        self.refreshInterval = Settings.refreshIntervalMinutes
        self.rankingMode = Settings.rankingMode
        self.learnFromNavigation = Settings.learnFromNavigation
        self.subfolderFrecency = Settings.subfolderFrecency
        self.minVisitCount = Settings.minVisitCount
        self.scanRoots = Settings.scanRoots
        self.editorTargets = Settings.editorTargetsOrDefault()
        self.terminalTarget = Settings.terminalTarget
        self.installedTerminals = Settings.detectInstalledTerminals()
    }

    // MARK: Hotkey recording

    func toggleRecording() {
        recording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        recording = true
        recordMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            if HotKeyUtils.isModifierKeyCode(event.keyCode) { return nil }
            let mods = HotKeyUtils.carbonModifiers(from: event.modifierFlags)
            // Escape with no modifiers cancels recording.
            if Int(event.keyCode) == kVK_Escape && mods == 0 {
                self.stopRecording(); return nil
            }
            guard mods != 0 else { return nil }   // require at least one modifier
            self.commit(keyCode: UInt32(event.keyCode), modifiers: mods)
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        if let m = recordMonitor { NSEvent.removeMonitor(m); recordMonitor = nil }
    }

    private func commit(keyCode: UInt32, modifiers: UInt32) {
        Settings.hotkeyKeyCode = keyCode
        Settings.hotkeyModifiers = modifiers
        hotkeyDisplay = HotKeyUtils.displayString(keyCode: keyCode, carbonModifiers: modifiers)
        stopRecording()
        NotificationCenter.default.post(name: .zffRemapHotKey, object: nil)
    }

    // MARK: Editors

    func autoDetectEditors() {
        let detected = Settings.detectInstalledEditors()
        // Merge: keep existing enabled-state for known bundle ids, add new ones.
        var byBundle = Dictionary(uniqueKeysWithValues: editorTargets.map { ($0.bundleID, $0) })
        for d in detected where byBundle[d.bundleID] == nil { byBundle[d.bundleID] = d }
        // Preserve current order, then append newly detected.
        var ordered = editorTargets
        for d in detected where !ordered.contains(where: { $0.bundleID == d.bundleID }) {
            ordered.append(byBundle[d.bundleID]!)
        }
        editorTargets = ordered
    }

    // MARK: Reset learned data

    func resetLearnedData() {
        let alert = NSAlert()
        alert.messageText = "Reset Learned Data?"
        alert.informativeText = "Forget every recorded visit and start ranking from scratch. Your files are never touched."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            appState?.resetLearnedData()
        }
    }

    // MARK: Launch at login

    private func applyLaunchAtLogin() {
        LaunchAtLogin.set(launchAtLogin)
    }
}

// MARK: - Root view

struct PreferencesView: View {
    @ObservedObject var model: PreferencesModel

    var body: some View {
        TabView {
            GeneralTab(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
            RankingTab(model: model)
                .tabItem { Label("Ranking", systemImage: "target") }
            FoldersTab(model: model)
                .tabItem { Label("Folders", systemImage: "folder") }
            OpenWithTab(model: model)
                .tabItem { Label("Open With", systemImage: "arrow.up.forward.app") }
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 420)
        .tint(.ember)   // brand accent replaces system blue across all controls
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var model: PreferencesModel

    var body: some View {
        Form {
            LabeledContent("Global shortcut") {
                HStack(spacing: 8) {
                    Text(model.recording ? "Press keys…" : model.hotkeyDisplay)
                        .font(.system(size: 13, weight: .medium))
                        .frame(minWidth: 110)
                        .padding(.vertical, 5).padding(.horizontal, 10)
                        .background(model.recording ? Color.ember.opacity(0.15) : Color(nsColor: .textBackgroundColor),
                                    in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                    Button(model.recording ? "Stop" : "Record…") { model.toggleRecording() }
                }
            }

            Toggle("Launch at login", isOn: $model.launchAtLogin)

            Picker("Appearance", selection: $model.appearance) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .pickerStyle(.segmented)
            .fixedSize()

            Picker("Refresh index", selection: $model.refreshInterval) {
                Text("Every 15 minutes").tag(15)
                Text("Every hour").tag(60)
                Text("Manually").tag(0)
            }
            .fixedSize()

            Divider()

            LabeledContent("Menu-bar icon") {
                Text("Haunts lives in the menu bar — there's no Dock icon.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            if model.launchAtLogin {
                Text("Launch-at-login only takes effect from a signed app bundle, not the debug build.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Ranking

private struct RankingTab: View {
    @ObservedObject var model: PreferencesModel

    private var modeDescription: String {
        model.rankingMode == "frequent"
        ? "Frequent (z-style). Ranks purely by where you go most, like the terminal z tool. Snappier for heavy navigators, but more willing to surface Downloads, temp and scratch folders."
        : "Balanced. Blends where you work (git projects, recent files) with how often you go there — and keeps noise like Downloads down-weighted. The recommended default."
    }

    var body: some View {
        Form {
            Picker("Ranking mode", selection: $model.rankingMode) {
                Text("Balanced").tag("balanced")
                Text("Frequent").tag("frequent")
            }
            .pickerStyle(.segmented)
            .fixedSize()

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(Color.ember)
                Text(modeDescription).font(.callout)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ember.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.ember.opacity(0.22)))

            Divider()

            Toggle("Learn from navigation", isOn: $model.learnFromNavigation)
            Text("Watches which folders you open in Finder so your most-used places rise to the top. (Live tracking lands in a later version; this only saves the preference for now.)")
                .font(.caption).foregroundStyle(.secondary)

            Divider()

            Toggle("Frequent subfolders", isOn: $model.subfolderFrecency)
            Text("Keep a subfolder you visit a lot as its own result instead of collapsing it into the project root.")
                .font(.caption).foregroundStyle(.secondary)
            Stepper("Keep after \(model.minVisitCount) visits",
                    value: $model.minVisitCount, in: 1...50)
                .disabled(!model.subfolderFrecency)

            Divider()

            LabeledContent("Learned data") {
                Button("Reset Learned Data…") { model.resetLearnedData() }
            }
            Text("Forget every recorded visit and start ranking from scratch. Asks to confirm; your files are never touched.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Folders

private struct FoldersTab: View {
    @ObservedObject var model: PreferencesModel
    @State private var selection: Int?

    var body: some View {
        Form {
            Section {
                List(selection: $selection) {
                    ForEach(Array(model.scanRoots.enumerated()), id: \.offset) { idx, root in
                        HStack(spacing: 10) {
                            Image(systemName: root.path == NSHomeDirectory() ? "house" : "folder")
                                .foregroundStyle(Color.ember)
                            Text(displayPath(root.path))
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Stepper("depth \(root.depth)", value: Binding(
                                get: { model.scanRoots[idx].depth },
                                set: { model.scanRoots[idx].depth = $0 }
                            ), in: 1...8)
                            .labelsHidden()
                            Text("depth \(root.depth)").foregroundStyle(.secondary).font(.callout)
                        }
                        .tag(idx)
                    }
                }
                .frame(minHeight: 150)

                HStack {
                    Button { chooseFolder() } label: { Image(systemName: "plus") }
                    Button { removeSelected() } label: { Image(systemName: "minus") }
                        .disabled(selection == nil)
                    Spacer()
                    Button("Choose folder…") { chooseFolder() }
                }
            } header: {
                Text("Scan roots")
            } footer: {
                Text("Haunts indexes git projects and folders under these locations. Ignores node_modules, Library, and hidden folders.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func displayPath(_ p: String) -> String {
        let home = NSHomeDirectory()
        return p == home ? "~" : (p.hasPrefix(home + "/") ? "~" + p.dropFirst(home.count) : p)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            if !model.scanRoots.contains(where: { $0.path == url.path }) {
                model.scanRoots.append(ScanRoot(path: url.path, depth: 3))
            }
        }
    }

    private func removeSelected() {
        guard let idx = selection, model.scanRoots.indices.contains(idx) else { return }
        model.scanRoots.remove(at: idx)
        selection = nil
    }
}

// MARK: - Open With

private struct OpenWithTab: View {
    @ObservedObject var model: PreferencesModel
    @State private var selection: EditorTarget.ID?

    var body: some View {
        Form {
            Section {
                List(selection: $selection) {
                    ForEach($model.editorTargets) { $target in
                        HStack(spacing: 10) {
                            Toggle("", isOn: $target.isEnabled).labelsHidden()
                            Image(systemName: "app").foregroundStyle(Color.ember)
                            Text(target.name)
                                .foregroundStyle(target.isEnabled ? .primary : .secondary)
                        }
                        .tag(target.id)
                    }
                    .onMove { from, to in model.editorTargets.move(fromOffsets: from, toOffset: to) }
                }
                .frame(minHeight: 130)

                HStack {
                    Button { removeSelected() } label: { Image(systemName: "minus") }
                        .disabled(selection == nil)
                    Spacer()
                    Button("Auto-detect installed") { model.autoDetectEditors() }
                }
            } header: {
                Text("Editor — ⌘↩ opens the top enabled editor")
            } footer: {
                Text("Drag to reorder. ↩ Finder · ⌘↩ editor · ⌃↩ terminal")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Picker("Terminal", selection: $model.terminalTarget) {
                ForEach(model.installedTerminals, id: \.self) { term in
                    Text(term).tag(term)
                }
            }
            .fixedSize()
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func removeSelected() {
        guard let id = selection else { return }
        model.editorTargets.removeAll { $0.id == id }
        selection = nil
    }
}

// MARK: - About

private struct AboutTab: View {
    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(v) (\(b))"
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: GhostIcon.aboutImage(size: 88))
                .frame(width: 88, height: 88)
                .background(
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .fill(RadialGradient(colors: [.emberGlow, .ember, .emberDeep],
                                             center: UnitPoint(x: 0.3, y: 0.2),
                                             startRadius: 2, endRadius: 96))
                        .shadow(color: .ember.opacity(0.5), radius: 14, y: 6)
                )
                .padding(.top, 10)

            Text("Haunts").font(.system(size: 23, weight: .semibold)).padding(.top, 12)
            Text(version).font(.caption).foregroundStyle(.secondary).padding(.top, 2)
            Text("“Jump to your haunts.”").font(.callout).italic()
                .foregroundStyle(.secondary).padding(.top, 8)

            Text("A keyboard-first navigator that learns where you work and takes you there instantly — no Dock icon, no fuss.")
                .font(.callout).multilineTextAlignment(.center)
                .frame(maxWidth: 380).padding(.top, 14)

            HStack(spacing: 8) {
                Button { open("https://www.buymeacoffee.com/rhydlewis") } label: {
                    Label("Buy me a coffee", systemImage: "cup.and.saucer.fill")
                }
                .buttonStyle(.borderedProminent).tint(.ember)
                Button("gethaunts.app") { open("https://gethaunts.app") }
                Button("GitHub") { open("https://github.com/rhydlewis/haunts") }
                Button("Acknowledgements") { open("https://gethaunts.app/acknowledgements") }
            }
            .padding(.top, 18)

            Text("Made with care by Rhyd Lewis · © 2026")
                .font(.caption).foregroundStyle(.secondary).padding(.top, 22)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func open(_ urlString: String) {
        if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
    }
}
