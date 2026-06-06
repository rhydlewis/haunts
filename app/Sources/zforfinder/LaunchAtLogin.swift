import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp`.
///
/// HONEST CAVEAT: this only actually registers a login item when running from a
/// signed `.app` bundle. From the bare SwiftPM debug binary the call throws
/// (no bundle identity), so it is effectively a no-op there — the preference is
/// still persisted by `Settings.launchAtLogin`, but nothing is registered.
enum LaunchAtLogin {
    static func set(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            NSLog("Haunts: launch-at-login \(enabled ? "register" : "unregister") failed (expected for unbundled debug build): \(error)")
        }
    }
}
