import Testing
import Foundation
@testable import HauntsCore

// MARK: - Pure install-vs-upgrade-vs-same decision

@Suite("AnalyticsDecisionTests")
struct AnalyticsDecisionTests {

    @Test func noStoredVersionIsInstall() {
        #expect(Analytics.launchEvent(lastSeen: nil, current: "0.1.0") == .install(version: "0.1.0"))
    }

    @Test func emptyStoredVersionIsInstall() {
        #expect(Analytics.launchEvent(lastSeen: "", current: "0.1.0") == .install(version: "0.1.0"))
    }

    @Test func sameVersionIsNone() {
        #expect(Analytics.launchEvent(lastSeen: "0.1.0", current: "0.1.0") == .none)
    }

    @Test func differentVersionIsUpgrade() {
        #expect(Analytics.launchEvent(lastSeen: "0.1.0", current: "0.1.1")
                == .upgrade(from: "0.1.0", to: "0.1.1"))
    }

    // A downgrade (older current than stored) is still a "version changed" event;
    // we report it as an upgrade-shaped transition rather than silently dropping it.
    @Test func downgradeIsReportedAsTransition() {
        #expect(Analytics.launchEvent(lastSeen: "0.2.0", current: "0.1.0")
                == .upgrade(from: "0.2.0", to: "0.1.0"))
    }
}

// MARK: - GoatCounter count URL construction

@Suite("AnalyticsURLTests")
struct AnalyticsURLTests {

    private func query(_ url: URL?) -> [String: String] {
        guard let url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    @Test func noneHasNoURL() {
        #expect(Analytics.countURL(for: .none) == nil)
    }

    @Test func installURLUsesInstallPathAndDefaultHost() {
        let url = Analytics.countURL(for: .install(version: "0.1.0"))
        #expect(url?.absoluteString.hasPrefix("https://haunts.goatcounter.com/count?") == true)
        let q = query(url)
        #expect(q["p"] == "/app/install/0.1.0")
        #expect(q["t"] == "Install 0.1.0")
    }

    @Test func upgradeURLEncodesTransition() {
        let url = Analytics.countURL(for: .upgrade(from: "0.1.0", to: "0.1.1"))
        let q = query(url)
        #expect(q["p"] == "/app/upgrade/0.1.0-to-0.1.1")
        #expect(q["t"] == "Upgrade 0.1.0 → 0.1.1")
    }

    @Test func customHostIsHonored() {
        let url = Analytics.countURL(for: .install(version: "1.0.0"),
                                     host: "http://localhost:8081")
        #expect(url?.absoluteString.hasPrefix("http://localhost:8081/count?") == true)
    }

    @Test func emittedURLIsValidAndPercentEncoded() {
        // The arrow in the upgrade title must survive as a real, parseable URL.
        let url = Analytics.countURL(for: .upgrade(from: "0.1.0", to: "0.1.1"))
        #expect(url != nil)
        #expect(url?.absoluteString.contains(" ") == false)   // spaces encoded
    }
}

// MARK: - reportLaunch wiring (decide → persist → send), fully injected

@Suite("AnalyticsReportLaunchTests")
struct AnalyticsReportLaunchTests {

    /// Captures the side effects of one reportLaunch call.
    private final class Spy {
        var persisted: [String] = []
        var sent: [URL] = []
    }

    private func run(current: String, lastSeen: String?) -> Spy {
        let spy = Spy()
        _ = Analytics.reportLaunch(
            current: current,
            lastSeen: lastSeen,
            persist: { spy.persisted.append($0) },
            send: { spy.sent.append($0) }
        )
        return spy
    }

    @Test func freshInstallPersistsAndSendsOnce() {
        let spy = run(current: "0.1.0", lastSeen: nil)
        #expect(spy.persisted == ["0.1.0"])
        #expect(spy.sent.count == 1)
        #expect(spy.sent.first?.absoluteString.contains("/app/install/0.1.0") == true)
    }

    @Test func upgradePersistsAndSendsOnce() {
        let spy = run(current: "0.1.1", lastSeen: "0.1.0")
        #expect(spy.persisted == ["0.1.1"])
        #expect(spy.sent.count == 1)
        #expect(spy.sent.first?.absoluteString.contains("/app/upgrade/0.1.0-to-0.1.1") == true)
    }

    @Test func sameVersionPersistsButSendsNothing() {
        let spy = run(current: "0.1.0", lastSeen: "0.1.0")
        #expect(spy.persisted == ["0.1.0"])   // always records last-seen
        #expect(spy.sent.isEmpty)             // but no ping when unchanged
    }

    @Test func returnsTheDecidedEvent() {
        let event = Analytics.reportLaunch(
            current: "0.2.0", lastSeen: "0.1.0",
            persist: { _ in }, send: { _ in }
        )
        #expect(event == .upgrade(from: "0.1.0", to: "0.2.0"))
    }
}

// MARK: - lastSeenVersion persistence

@Suite("LastSeenVersionTests", .serialized)
struct LastSeenVersionTests {

    private func clear() { UserDefaults.standard.removeObject(forKey: "haunts.lastSeenVersion") }

    @Test func absentIsNil() {
        clear()
        #expect(Settings.lastSeenVersion == nil)
    }

    @Test func roundTrips() {
        clear()
        Settings.lastSeenVersion = "0.1.1"
        #expect(Settings.lastSeenVersion == "0.1.1")
        clear()
    }
}
