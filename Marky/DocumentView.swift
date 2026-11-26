import SwiftUI

struct DocumentView: View {
    @ObservedObject var model: DocumentModel
    @AppStorage(SettingsKey.sidebarWidth) private var sidebarWidth: Double = 240
    @State private var dragStartWidth: Double?

    var body: some View {
        // A plain HStack instead of NavigationSplitView: the split view lays the
        // sidebar out visible and then animates it away on load, which flashed it
        // and left squeezed text behind. This starts in the right state and
        // slides only when toggled.
        HStack(spacing: 0) {
            if model.sidebarVisible {
                Sidebar(model: model)
                    .frame(width: sidebarWidth)
                    .background(VisualEffect(material: .sidebar).ignoresSafeArea())
                    .overlay(alignment: .trailing) { resizeHandle }
                    .transition(.move(edge: .leading))
                Divider().ignoresSafeArea()
            }
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
        .clipped()
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { model.toggleSidebar() } label: { Image(systemName: "sidebar.left") }
                    .help(model.sidebarVisible ? "Hide Sidebar" : "Show Sidebar")
            }
        }
        .navigationTitle(model.displayName)
        .navigationSubtitle(model.fileURL.deletingLastPathComponent().lastPathComponent)
        .navigationDocument(model.fileURL)
        .frame(minWidth: 420, minHeight: 300)
    }

    private var resizeHandle: some View {
        Color.clear
            .frame(width: 6)
            .contentShape(Rectangle())
            .onHover { inside in inside ? NSCursor.resizeLeftRight.push() : NSCursor.pop() }
            .gesture(DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let start = dragStartWidth ?? sidebarWidth
                    dragStartWidth = start
                    sidebarWidth = min(420, max(170, start + value.translation.width))
                }
                .onEnded { _ in dragStartWidth = nil })
    }
}

/// NSVisualEffectView, for the translucent sidebar background.
private struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private struct Sidebar: View {
    @ObservedObject var model: DocumentModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("Sidebar", selection: $model.sidebarMode) {
                Text("Files").tag(SidebarMode.files)
                Text("Outline").tag(SidebarMode.outline)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            switch model.sidebarMode {
            case .files: FilesView(model: model)
            case .outline: OutlineView(model: model)
            }
        }
    }
}

// MARK: - Files

private struct FilesView: View {
    @ObservedObject var model: DocumentModel

    var body: some View {
        // Selecting a row (click or arrow keys) shows that file in this tab.
        let selection = Binding<URL?>(
            get: { model.fileURL },
            set: { url in if let url { model.navigate(to: url) } })

        List(selection: selection) {
            Section(model.rootURL.lastPathComponent) {
                ForEach(model.tree) { FileRow(node: $0, model: model) }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if model.tree.isEmpty {
                Text("No Markdown files").foregroundStyle(.secondary)
            }
        }
    }
}

private struct FileRow: View {
    let node: FileNode
    @ObservedObject var model: DocumentModel

    var body: some View {
        if let children = node.children {
            DisclosureGroup(isExpanded: Binding(
                get: { model.expanded.contains(node.url) },
                set: { open in
                    if open { model.expanded.insert(node.url) } else { model.expanded.remove(node.url) }
                })
            ) {
                ForEach(children) { FileRow(node: $0, model: model) }
            } label: {
                Label(node.name, systemImage: "folder")
            }
        } else {
            Label(node.name, systemImage: "doc.text")
                .lineLimit(1)
                .help(node.url.path)
                .tag(node.url)
                // Outside a split view the sidebar list doesn't paint its selection; draw it.
                .listRowBackground(
                    node.url == model.fileURL
                        ? RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.1)).padding(.horizontal, 10)
                        : nil)
                .contextMenu {
                    Button("Open in New Tab") { WindowManager.shared.open(node.url, nextTo: model.webView?.window) }
                    Button("Open in New Window") { WindowManager.shared.open(node.url, newWindow: true) }
                    Divider()
                    Button("Reveal in Finder") { model.revealInFinder(node.url) }
                }
        }
    }
}

// MARK: - Outline

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

// MARK: - Find

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
