import SwiftUI

struct DocumentView: View {
    @StateObject private var model: DocumentModel
    @State private var columnVisibility: NavigationSplitViewVisibility

    init(text: String, fileURL: URL?) {
        _model = StateObject(wrappedValue: DocumentModel(text: text, fileURL: fileURL))
        let showOutline = UserDefaults.standard.object(forKey: SettingsKey.showOutline) as? Bool ?? false
        _columnVisibility = State(initialValue: showOutline ? .all : .detailOnly)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            OutlineView(model: model)
                .navigationSplitViewColumnWidth(min: 170, ideal: 230, max: 360)
        } detail: {
            MarkdownWebView(model: model)
                .overlay(alignment: .topTrailing) {
                    if model.findVisible {
                        FindBar(model: model)
                            .padding(10)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.easeOut(duration: 0.15), value: model.findVisible)
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .navigationTitle(model.displayName)
        .navigationSubtitle(model.title.flatMap { $0 == model.displayName ? nil : $0 } ?? "")
        .focusedSceneObject(model)
        .frame(minWidth: 420, minHeight: 300)
    }
}

private struct OutlineView: View {
    @ObservedObject var model: DocumentModel

    var body: some View {
        if model.headings.isEmpty {
            Text("No headings")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let minLevel = model.headings.map(\.level).min() ?? 1
            List(model.headings) { heading in
                Button {
                    model.scrollTo(headingID: heading.id)
                } label: {
                    Text(heading.text)
                        .lineLimit(2)
                        .font(heading.level == minLevel ? .body.weight(.medium) : .body)
                        .foregroundStyle(heading.level <= minLevel + 1 ? .primary : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, CGFloat(heading.level - minLevel) * 12)
                .help(heading.text)
            }
            .listStyle(.sidebar)
        }
    }
}

private struct FindBar: View {
    @ObservedObject var model: DocumentModel
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find", text: $model.findQuery)
                .textFieldStyle(.plain)
                .frame(width: 180)
                .focused($fieldFocused)
                .onSubmit { model.find(direction: 1) }
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.shift) else { return .ignored }
                    model.find(direction: -1)
                    return .handled
                }
                .onChange(of: model.findQuery) { _, _ in model.find(direction: 0) }

            if !model.findQuery.isEmpty {
                Text(model.findCount == 0 ? "No matches" : "\(model.findIndex) of \(model.findCount)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }

            Divider().frame(height: 16)
            Button { model.find(direction: -1) } label: { Image(systemName: "chevron.up") }
                .help("Previous (⇧⌘G)")
                .disabled(model.findCount == 0)
            Button { model.find(direction: 1) } label: { Image(systemName: "chevron.down") }
                .help("Next (⌘G)")
                .disabled(model.findCount == 0)
            Button { model.closeFind() } label: { Image(systemName: "xmark.circle.fill") }
                .help("Close (Esc)")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .onExitCommand { model.closeFind() }
        .onAppear { fieldFocused = true }
        .onChange(of: model.findFocusRequest) { _, _ in fieldFocused = true }
    }
}
