import Testing
import Foundation
@testable import ZFFEngine
@testable import HauntsAdapters
@testable import HauntsCore

// MARK: - Helpers

private func makeTempStore() -> (Store, URL, () -> Void) {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("AdapterWiringTests-\(UUID().uuidString)", isDirectory: true)
    let file = dir.appendingPathComponent("frecency.json")
    let store = Store(fileURL: file)
    return (store, dir, { try? FileManager.default.removeItem(at: dir) })
}

// MARK: - Stub adapters

private struct StubAdapter: EditorAdapter {
    var editorName: String { "Stub" }
    let urls: [URL]
    func recentFolders() throws -> [URL] { urls }
}

private struct ThrowingAdapter: EditorAdapter {
    var editorName: String { "Thrower" }
    struct E: Error {}
    func recentFolders() throws -> [URL] { throw E() }
}

// MARK: - rebuild() adapter wiring

struct AdapterWiringRebuildTests {

    @Test @MainActor func adapterPathAppearsInIndexAfterRebuild() {
        let (store, _, cleanup) = makeTempStore()
        defer { cleanup() }

        let stub = StubAdapter(urls: [URL(fileURLWithPath: "/tmp/adapter-only-path")])
        let state = AppState(store: store, adapters: [stub])
        state.rebuild()

        let paths = state.index.map(\.path)
        #expect(paths.contains("/tmp/adapter-only-path"),
                "Path returned by adapter must appear in AppState.index after rebuild()")
    }

    @Test @MainActor func multipleAdapterPathsAllAppearInIndex() {
        let (store, _, cleanup) = makeTempStore()
        defer { cleanup() }

        let stub = StubAdapter(urls: [
            URL(fileURLWithPath: "/tmp/adapter-path-1"),
            URL(fileURLWithPath: "/tmp/adapter-path-2"),
        ])
        let state = AppState(store: store, adapters: [stub])
        state.rebuild()

        let paths = state.index.map(\.path)
        #expect(paths.contains("/tmp/adapter-path-1"))
        #expect(paths.contains("/tmp/adapter-path-2"))
    }

    @Test @MainActor func emptyAdapterListDoesNotCrash() {
        let (store, _, cleanup) = makeTempStore()
        defer { cleanup() }

        let state = AppState(store: store, adapters: [])
        state.rebuild()
        // No assertion needed — just must not crash/throw
        _ = state.index
    }
}

// MARK: - rebuild() adapter failure isolation

struct AdapterFailureIsolationTests {

    @Test @MainActor func throwingAdapterDoesNotAbortRebuild() {
        let (store, _, cleanup) = makeTempStore()
        defer { cleanup() }

        let thrower = ThrowingAdapter()
        let stub = StubAdapter(urls: [URL(fileURLWithPath: "/tmp/good-adapter-path")])
        let state = AppState(store: store, adapters: [thrower, stub])
        state.rebuild()

        let paths = state.index.map(\.path)
        #expect(paths.contains("/tmp/good-adapter-path"),
                "Path from non-failing adapter must appear even when another adapter throws")
    }

    @Test @MainActor func allThrowingAdaptersProducesEmptyOrGitIndex() {
        let (store, _, cleanup) = makeTempStore()
        defer { cleanup() }

        let state = AppState(store: store, adapters: [ThrowingAdapter(), ThrowingAdapter()])
        // Must not throw or crash
        state.rebuild()
        _ = state.index
    }
}
