import Testing
import Foundation
@testable import ZFFEngine
@testable import HauntsCore

// The tracker's dedupe + filter + record wiring, exercised with an injected poll
// closure so it runs deterministically on CI (the real Apple Events poll needs a
// GUI + Finder + consent and is verified manually). `tick()` is driven by hand
// here instead of via the live Timer.
@MainActor
struct FinderTrackerTests {
    private func tempStore() -> (Store, () -> Void) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FinderTrack-\(UUID().uuidString)", isDirectory: true)
        let store = Store(fileURL: dir.appendingPathComponent("frecency.json"))
        return (store, { try? FileManager.default.removeItem(at: dir) })
    }

    /// A tracker whose poll replays `paths` one entry per tick (then keeps returning
    /// the last). Returns the tracker plus the live AppState/store for assertions.
    private func make(_ paths: [String?]) -> (FinderTracker, AppState, Store, () -> Void) {
        let (store, cleanup) = tempStore()
        let state = AppState(store: store, adapters: [])
        state.rebuild()
        var i = 0
        let tracker = FinderTracker(interval: 2) {
            defer { if i < paths.count - 1 { i += 1 } }
            return paths.isEmpty ? nil : paths[i]
        }
        tracker.bind(appState: state)
        return (tracker, state, store, cleanup)
    }

    private func recordCount(_ store: Store, _ path: String) -> Int {
        store.load().filter { $0.path == path }.reduce(0) { $0 + $1.visitCount }
    }

    @Test func recordsANavigatedFolder() {
        let p = "/Users/rhyd/code/zff-fixture"
        let (tracker, state, store, cleanup) = make([p + "/"]); defer { cleanup() }
        tracker.tick()
        #expect(recordCount(store, p) == 1)
        #expect(state.index.contains { $0.path == p })
    }

    @Test func dedupesConsecutiveIdenticalPaths() {
        let p = "/Users/rhyd/code/zff-dedupe"
        let (tracker, state, store, cleanup) = make([p, p, p]); defer { cleanup() }
        withExtendedLifetime(state) {
            tracker.tick(); tracker.tick(); tracker.tick()
        }
        #expect(recordCount(store, p) == 1)   // same folder, recorded once
    }

    @Test func recordsEachDistinctFolderChange() {
        let a = "/Users/rhyd/code/aaa"
        let b = "/Users/rhyd/code/bbb"
        let (tracker, state, store, cleanup) = make([a, b, a]); defer { cleanup() }
        withExtendedLifetime(state) {
            tracker.tick(); tracker.tick(); tracker.tick()
        }
        #expect(recordCount(store, a) == 2)   // A then back to A
        #expect(recordCount(store, b) == 1)
    }

    @Test func skipsFilteredLocations() {
        let (tracker, state, store, cleanup) = make(["/Applications/Utilities"]); defer { cleanup() }
        withExtendedLifetime(state) { tracker.tick() }
        #expect(store.load().isEmpty)
    }

    @Test func filteredPathDoesNotBlockLaterRealFolder() {
        let real = "/Users/rhyd/code/after-apps"
        let (tracker, state, store, cleanup) = make(["/Applications", real]); defer { cleanup() }
        withExtendedLifetime(state) {
            tracker.tick(); tracker.tick()
        }
        #expect(recordCount(store, real) == 1)
    }

    @Test func nilPollIsDroppedSilently() {
        // error / no-window / consent-denied → poll returns nil → no record, no crash.
        let (tracker, state, store, cleanup) = make([String?.none]); defer { cleanup() }
        withExtendedLifetime(state) { tracker.tick() }
        #expect(store.load().isEmpty)
    }

    @Test func nilPollRetainsLastPathForDedupe() {
        let p = "/Users/rhyd/code/retain"
        // p (record) → nil (transient error) → p again (should NOT re-record: still same folder)
        let (tracker, state, store, cleanup) = make([p, nil, p]); defer { cleanup() }
        withExtendedLifetime(state) {
            tracker.tick(); tracker.tick(); tracker.tick()
        }
        #expect(recordCount(store, p) == 1)
    }

    @Test func startStopTogglesRunning() {
        let (store, cleanup) = tempStore(); defer { cleanup() }
        let state = AppState(store: store, adapters: [])
        let tracker = FinderTracker(interval: 2) { nil }
        #expect(!tracker.isRunning)
        tracker.start(appState: state)
        #expect(tracker.isRunning)
        tracker.stop()
        #expect(!tracker.isRunning)
    }

    @Test func startIsIdempotent() {
        let (store, cleanup) = tempStore(); defer { cleanup() }
        let state = AppState(store: store, adapters: [])
        let tracker = FinderTracker(interval: 2) { nil }
        tracker.start(appState: state)
        tracker.start(appState: state)   // second start must not double-schedule or crash
        #expect(tracker.isRunning)
        tracker.stop()
    }
}
