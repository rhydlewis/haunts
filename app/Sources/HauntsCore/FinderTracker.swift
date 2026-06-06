import Foundation

/// Live-navigation tracker (spike bf7, bead jrc). Polls Finder's front-window
/// target folder every ~2s via Apple Events and feeds folder *changes* into
/// `AppState.trackNavigation`, so the frecency store learns where you actually work.
///
/// Design constraints, learned the hard way:
/// - **NSAppleScript is main-thread only.** This whole type is `@MainActor`; the
///   poll runs synchronously on the main run loop via a scheduled `Timer`. Each
///   call is a quick `tell application "Finder"` round-trip — we never block for 2s.
/// - **`target of front Finder window`, not `insertion location`** (bf7): the latter
///   diverges to a *selected* subfolder rather than the folder you're viewing.
/// - **Never crash or busy-spin.** On error / no window / consent-denied (-1743) the
///   poll returns `nil`; we drop the tick silently and keep the last known path.
/// - **Dedupe + filter are pure** (`NavigationFilter`) and unit-tested; CI can't run
///   the Apple Events poll itself (needs GUI + Finder + Automation consent).
@MainActor
public final class FinderTracker {
    private weak var appState: AppState?
    private var timer: Timer?
    private var lastPath: String?
    private let interval: TimeInterval
    private let poll: @MainActor () -> String?

    /// - Parameters:
    ///   - interval: poll period in seconds (default 2).
    ///   - poll: returns the raw front-window POSIX path, or `nil` on any failure.
    ///           Injectable so tests drive it deterministically; defaults to the
    ///           real Apple Events query.
    public nonisolated init(interval: TimeInterval = 2,
                            poll: @escaping @MainActor () -> String? = FinderTracker.frontFinderWindowPath) {
        self.interval = interval
        self.poll = poll
    }

    public var isRunning: Bool { timer != nil }

    /// Wire an AppState without scheduling the timer — used by tests that drive
    /// `tick()` by hand. `start` is the production entry point.
    func bind(appState: AppState) { self.appState = appState }

    /// Begin polling. Idempotent: a second call while running is a no-op (so we
    /// never double-schedule). Reads once immediately so a folder already open is
    /// captured without waiting a full interval.
    public func start(appState: AppState) {
        guard timer == nil else { return }
        self.appState = appState
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    /// Stop polling. Off means off — no timer, no Apple Events traffic.
    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// One poll cycle: read → normalise → dedupe → filter → record. Internal so
    /// tests can step it; production drives it from the `Timer`.
    func tick() {
        guard let raw = poll(), let path = NavigationFilter.normalize(raw) else {
            return   // failure or junk: drop silently, keep lastPath
        }
        guard path != lastPath else { return }   // same folder as last tick → dedupe
        lastPath = path                            // remember even if we won't record it
        guard NavigationFilter.shouldRecord(path) else { return }
        appState?.trackNavigation(path: URL(fileURLWithPath: path))
    }

    /// Read `target of front Finder window` as a POSIX path via Apple Events.
    /// Returns `nil` on no window, any AppleScript error, or denied consent (-1743).
    /// Based on the validated probe in `spikes/finder-track-probe.swift`.
    public static func frontFinderWindowPath() -> String? {
        let source = """
        tell application "Finder"
            try
                if (count of Finder windows) is 0 then return ""
                return POSIX path of (target of front Finder window as alias)
            on error
                return ""
            end try
        end tell
        """
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if error != nil { return nil }
        let path = result.stringValue ?? ""
        return path.isEmpty ? nil : path
    }
}
