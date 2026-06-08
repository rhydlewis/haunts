import Foundation
import ServiceManagement

/// Headless self-check for the assembled `.app` bundle, invoked with
/// `Haunts.app/Contents/MacOS/Haunts --diagnostics`.
///
/// It reports what `Bundle.main` actually resolves at runtime (so we know the
/// real Info.plist is in effect, not the linker-embedded dev plist) and exercises
/// the SAME `SMAppService.mainApp` call the Launch-at-login toggle makes — which
/// is otherwise only reachable by clicking the Preferences UI. On a locked screen
/// that click is impossible, so this is how we VERIFY (not assert) registration.
///
/// It leaves system state clean: if it registers a login item that wasn't there
/// before, it unregisters again before exiting.
enum Diagnostics {
    static func run() {
        let b = Bundle.main
        print("bundleIdentifier   = \(b.bundleIdentifier ?? "<nil>")")
        print("CFBundleName       = \(b.infoDictionary?["CFBundleName"] as? String ?? "<nil>")")
        print("ShortVersionString = \(b.infoDictionary?["CFBundleShortVersionString"] as? String ?? "<nil>")")
        print("BundleVersion      = \(b.infoDictionary?["CFBundleVersion"] as? String ?? "<nil>")")
        print("LSUIElement        = \(b.infoDictionary?["LSUIElement"] as? Bool ?? false)")
        print("NSAccentColorName  = \(b.infoDictionary?["NSAccentColorName"] as? String ?? "<nil>")")
        print("bundlePath         = \(b.bundlePath)")

        guard #available(macOS 13.0, *) else {
            print("launch-at-login    = SKIPPED (needs macOS 13+)")
            return
        }
        let svc = SMAppService.mainApp
        let before = svc.status
        print("SMAppService.status (before) = \(describe(before))")
        let wasEnabled = before == .enabled
        do {
            try svc.register()
            print("SMAppService.register() = OK")
            print("SMAppService.status (after register) = \(describe(svc.status))")
            // Restore prior state so we don't silently add a login item.
            if !wasEnabled {
                try svc.unregister()
                print("SMAppService.unregister() = OK (restored prior state)")
            }
        } catch {
            print("SMAppService.register() = FAILED: \(error.localizedDescription)")
            print("  (expected for an UNSIGNED bundle — see bead 4fd signing. macOS")
            print("   often requires user approval in Login Items until the app is signed.)")
        }
    }

    /// Unregister this bundle's login item (the `--unregister-login` flag). Idempotent.
    static func unregisterLogin() {
        guard #available(macOS 13.0, *) else {
            print("unregister-login = SKIPPED (needs macOS 13+)")
            return
        }
        let svc = SMAppService.mainApp
        print("SMAppService.status (before) = \(describe(svc.status))")
        do {
            try svc.unregister()
            print("SMAppService.unregister() = OK")
        } catch {
            print("SMAppService.unregister() = FAILED: \(error.localizedDescription)")
        }
        print("SMAppService.status (after)  = \(describe(svc.status))")
    }

    @available(macOS 13.0, *)
    private static func describe(_ s: SMAppService.Status) -> String {
        switch s {
        case .notRegistered:  return "notRegistered"
        case .enabled:        return "enabled"
        case .requiresApproval: return "requiresApproval"
        case .notFound:       return "notFound"
        @unknown default:     return "unknown(\(s.rawValue))"
        }
    }
}
