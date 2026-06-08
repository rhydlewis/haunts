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
                    .foregroundStyle(Color.ember)
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
            .strokeBorder(.primary.opacity(0.12), lineWidth: 1))   // adaptive rim (dark→light, light→dark)
        .onAppear { focused = true }
        .onChange(of: state.focusPing) { _, _ in focused = true }
        .onChange(of: state.query) { _, _ in state.selection = 0 }
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key).padding(.horizontal, 5).padding(.vertical, 1)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            Text(label)
        }
    }
}

private struct Row: View {
    let place: Place
    let selected: Bool
    @Environment(\.colorScheme) private var scheme

    // Brand orange/teal read well on the dark material; on the light (and
    // wallpaper-tinted, translucent) material they wash out, so fall back to the
    // vibrancy-aware system label colors that stay legible on any background.
    private var scoreColor: Color { scheme == .dark ? .ember : Color(nsColor: .secondaryLabelColor) }
    private var repoColor: Color { scheme == .dark ? .teal : Color(nsColor: .labelColor) }
    private var repoFill: Color { scheme == .dark ? .teal.opacity(0.12) : Color.primary.opacity(0.07) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: place.isRepo ? "arrow.triangle.branch" : "folder")
                .font(.system(size: 14))
                .frame(width: 30, height: 30)
                .background(selected ? AnyShapeStyle(Color.ember) : AnyShapeStyle(.quaternary),
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
                    .foregroundStyle(repoColor)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(repoFill, in: RoundedRectangle(cornerRadius: 5))
            }
            Text(String(format: "%.1f", place.score))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(scoreColor)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(selected ? AnyShapeStyle(Color.ember.opacity(0.18)) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 10))
    }
}

extension Notification.Name {
    static let zffHide = Notification.Name("zffHide")
}
