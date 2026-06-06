import SwiftUI
import ZFFEngine
import HauntsCore

struct PaletteView: View {
    @EnvironmentObject var state: AppState
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // search field
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.orange.opacity(0.9))
                TextField("jump to…", text: $state.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .light, design: .rounded))
                    .focused($focused)
            }
            .padding(.horizontal, 20).padding(.vertical, 18)

            Divider().opacity(0.4)

            // results — identity by path only (no positional .id override)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(state.results.enumerated()), id: \.element.id) { idx, place in
                            Row(place: place, selected: idx == state.selection)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    state.selection = idx
                                    state.activate(.finder)
                                    NotificationCenter.default.post(name: .zffHide, object: nil)
                                }
                        }
                    }
                    .padding(6)
                }
                .onChange(of: state.selection) { _, sel in
                    if state.results.indices.contains(sel) {
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(state.results[sel].id, anchor: .center)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)

            Divider().opacity(0.4)

            // footer
            HStack(spacing: 18) {
                hint("↩", "Finder"); hint("⌘↩", "editor"); hint("⌃↩", "terminal")
                Spacer()
                hint("esc", "close")
            }
            .padding(.horizontal, 18).padding(.vertical, 11)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .frame(width: 640, height: 420)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(.white.opacity(0.10), lineWidth: 1))
        .onAppear { focused = true }
        .onChange(of: state.focusPing) { _, _ in focused = true }
        .onChange(of: state.query) { _, _ in state.selection = 0 }
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key).padding(.horizontal, 5).padding(.vertical, 1)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
            Text(label)
        }
    }
}

private struct Row: View {
    let place: Place
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: place.isRepo ? "arrow.triangle.branch" : "folder")
                .font(.system(size: 14))
                .frame(width: 30, height: 30)
                .background(selected ? AnyShapeStyle(.orange) : AnyShapeStyle(.white.opacity(0.06)),
                            in: RoundedRectangle(cornerRadius: 7))
                .foregroundStyle(selected ? AnyShapeStyle(.black) : AnyShapeStyle(.primary))

            VStack(alignment: .leading, spacing: 1) {
                Text(place.name).font(.system(size: 15)).lineLimit(1)
                Text(place.display).font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
            Spacer()
            if place.isRepo {
                Text("repo").font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.teal)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
            }
            Text(String(format: "%.1f", place.score))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.orange.opacity(0.8))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(selected ? AnyShapeStyle(.orange.opacity(0.16)) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 10))
    }
}

extension Notification.Name {
    static let zffHide = Notification.Name("zffHide")
}
