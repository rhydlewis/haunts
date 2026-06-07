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

    // Passive navigation is tagged .nav (not .jump) so it stays out of usage stats.
    @Test @MainActor func trackNavigationIsTaggedNav() {
        let (store, cleanup) = tempStore(); defer { cleanup() }
        let state = AppState(store: store, adapters: [])
        state.rebuild()
        let p = "/tmp/zff-nav-origin"
        state.trackNavigation(path: URL(fileURLWithPath: p))
        let recs = store.load().filter { $0.path == p }
        #expect(recs.allSatisfy { $0.origin == .nav })
        #expect(Store.totalJumps(store.load()) == 0)
    }
}

// MARK: - Explicit jumps (palette activation feeds ranking + usage stats)

struct ExplicitJumpTests {
    private func tempStore() -> (Store, () -> Void) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("Jump-\(UUID().uuidString)", isDirectory: true)
        let store = Store(fileURL: dir.appendingPathComponent("frecency.json"))
        return (store, { try? FileManager.default.removeItem(at: dir) })
    }

    // An explicit jump persists as .jump AND surfaces in the live index.
    @Test @MainActor func recordJumpStoresJumpAndSurfaces() {
        let (store, cleanup) = tempStore(); defer { cleanup() }
        let state = AppState(store: store, adapters: [])
        state.rebuild()
        let p = "/tmp/zff-jump-fixture"
        state.recordJump(path: URL(fileURLWithPath: p))
        let recs = store.load().filter { $0.path == p }
        #expect(recs.contains { $0.origin == .jump })
        #expect(Store.totalJumps(store.load()) == 1)
        #expect(state.index.contains { $0.path == p })
    }

    // More explicit jumps raise that folder's score in the live index.
    @Test @MainActor func repeatedJumpsRaiseRank() {
        let (store, cleanup) = tempStore(); defer { cleanup() }
        let state = AppState(store: store, adapters: [])
        state.rebuild()
        let p = URL(fileURLWithPath: "/tmp/zff-jump-rank")
        state.recordJump(path: p)
        let after1 = state.index.first { $0.path == p.path }?.score ?? 0
        state.recordJump(path: p)
        state.recordJump(path: p)
        state.recordJump(path: p)
        let after4 = state.index.first { $0.path == p.path }?.score ?? 0
        #expect(after4 > after1, "more explicit jumps must raise the folder's score")
    }

    // The full wiring: activating the selected result routes through open() and
    // records exactly one explicit jump. Uses a nonexistent /tmp path so the
    // NSWorkspace open is a silent no-op (no Finder window).
    @Test @MainActor func activateOnSelectionRecordsJump() {
        let (store, cleanup) = tempStore(); defer { cleanup() }
        let state = AppState(store: store, adapters: [])
        state.rebuild()
        let name = "zff-activate-\(UUID().uuidString)"
        let p = "/tmp/\(name)"
        state.recordJump(path: URL(fileURLWithPath: p))   // seed it into the index
        state.query = name                                // isolate it as the only result
        state.selection = 0
        #expect(state.results.first?.path == p)
        let before = store.load().filter { $0.path == p && $0.origin == .jump }.count
        state.activate(.finder)
        let after = store.load().filter { $0.path == p && $0.origin == .jump }.count
        #expect(after == before + 1, "activate → open must record exactly one explicit jump")
    }
}
