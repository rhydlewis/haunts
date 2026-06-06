import Testing
import Foundation
@testable import ZFFEngine
@testable import HauntsCore

struct TrackNavigationSinkTests {
    private func tempStore() -> (Store, () -> Void) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("TrackNav-\(UUID().uuidString)", isDirectory: true)
        let store = Store(fileURL: dir.appendingPathComponent("frecency.json"))
        return (store, { try? FileManager.default.removeItem(at: dir) })
    }

    // A tracked visit is persisted AND surfaces in the live index.
    @Test @MainActor func trackNavigationRecordsAndSurfaces() {
        let (store, cleanup) = tempStore(); defer { cleanup() }
        let state = AppState(store: store, adapters: [])
        state.rebuild()
        let p = "/tmp/zff-track-fixture"
        state.trackNavigation(path: URL(fileURLWithPath: p))
        #expect(store.load().contains { $0.path == p })
        #expect(state.index.contains { $0.path == p })
    }

    // Forgetting a tracked folder removes it from BOTH the store and the live index.
    @Test @MainActor func forgetRemovesFromStoreAndIndex() {
        let (store, cleanup) = tempStore(); defer { cleanup() }
        let state = AppState(store: store, adapters: [])
        state.rebuild()
        let p = "/tmp/zff-forget-fixture"
        state.trackNavigation(path: URL(fileURLWithPath: p))
        #expect(state.index.contains { $0.path == p })

        state.forget(path: p)
        #expect(!store.load().contains { $0.path == p }, "records must be gone from the store")
        #expect(!state.index.contains { $0.path == p }, "row must be gone from the live index")
    }

    // Repeated navigation accumulates visit records.
    @Test @MainActor func repeatedNavigationAccumulatesVisits() {
        let (store, cleanup) = tempStore(); defer { cleanup() }
        let state = AppState(store: store, adapters: [])
        state.rebuild()
        let p = URL(fileURLWithPath: "/tmp/zff-track-repeat")
        state.trackNavigation(path: p)
        state.trackNavigation(path: p)
        state.trackNavigation(path: p)
        let total = store.load().filter { $0.path == p.path }.reduce(0) { $0 + $1.visitCount }
        #expect(total == 3)
    }
}
