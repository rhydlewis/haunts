import Foundation

/// Anonymous install/upgrade counting via GoatCounter (haunts.goatcounter.com).
///
/// This is the ONLY thing Haunts ever sends off the Mac. It is strictly
/// anonymous: no identifiers, no file paths, no navigation or usage data — just
/// a single count when the app is first installed or upgraded to a new version.
/// It is not configurable; the behaviour is disclosed in the privacy/help copy
/// on gethaunts.app.
///
/// The DECISION (install vs upgrade vs same) is a pure function and unit-tested;
/// the network call is the impure, fail-silent, non-blocking shell.
public enum Analytics {

    /// What a launch should report, derived purely from the last-seen and
    /// current app versions.
    public enum LaunchEvent: Equatable, Sendable {
        case install(version: String)
        case upgrade(from: String, to: String)
        case none
    }

    public static let defaultHost = "https://haunts.goatcounter.com"

    // MARK: - Pure logic

    /// Decide what to report given the previously stored version and the current
    /// one. No stored version ⇒ install; different ⇒ upgrade; equal ⇒ nothing.
    public static func launchEvent(lastSeen: String?, current: String) -> LaunchEvent {
        guard let last = lastSeen, !last.isEmpty else { return .install(version: current) }
        if last == current { return .none }
        return .upgrade(from: last, to: current)
    }

    /// Build the GoatCounter `count` URL for an event. Returns nil for `.none`
    /// (nothing to send). GoatCounter counts these synthetic paths like
    /// pageviews — no JS, no API token (a token in a distributed app would be
    /// extractable).
    public static func countURL(for event: LaunchEvent, host: String = defaultHost) -> URL? {
        let path: String
        let title: String
        switch event {
        case .none:
            return nil
        case .install(let version):
            path = "/app/install/\(version)"
            title = "Install \(version)"
        case .upgrade(let from, let to):
            path = "/app/upgrade/\(from)-to-\(to)"
            title = "Upgrade \(from) → \(to)"
        }
        guard var comps = URLComponents(string: host + "/count") else { return nil }
        comps.queryItems = [
            URLQueryItem(name: "p", value: path),
            URLQueryItem(name: "t", value: title),
        ]
        return comps.url
    }

    // MARK: - Impure shell

    /// Decide, persist the current version locally, and fire one anonymous ping
    /// on a version change. Fail-silent and non-blocking — the network call is a
    /// fire-and-forget `URLSession` task whose result is ignored, and nothing
    /// here ever delays or blocks launch. Parameters are injectable for tests.
    @discardableResult
    public static func reportLaunch(
        current: String = currentAppVersion(),
        lastSeen: String? = Settings.lastSeenVersion,
        persist: (String) -> Void = { Settings.lastSeenVersion = $0 },
        send: (URL) -> Void = defaultSend,
        firstLaunchDate: Date? = Settings.firstLaunchDate,
        stampFirstLaunch: (Date) -> Void = { Settings.firstLaunchDate = $0 },
        now: Date = Date()
    ) -> LaunchEvent {
        let event = launchEvent(lastSeen: lastSeen, current: current)
        persist(current)
        // Stamp firstLaunchDate once and never overwrite. A fresh install has no
        // stored date, so this fires on .install; for users who installed before
        // the field existed it's a best-effort fallback on their next launch.
        if firstLaunchDate == nil {
            stampFirstLaunch(now)
        }
        guard let url = countURL(for: event) else { return event }
        send(url)
        return event
    }

    /// Current app version from the bundle (`CFBundleShortVersionString`).
    public static func currentAppVersion() -> String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }

    /// Fire-and-forget anonymous GET. Ignores every result and error; never
    /// blocks the caller (the `dataTask` runs asynchronously).
    public static func defaultSend(_ url: URL) {
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "GET"
        req.setValue("Haunts/\(currentAppVersion()) (macOS; install-analytics)",
                     forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req).resume()
    }
}
