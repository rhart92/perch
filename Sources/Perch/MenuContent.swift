import AppKit
import SwiftUI
import PerchCore

// Select the property wrapper explicitly; recent SDKs also export a State macro.
private typealias ViewState<Value> = SwiftUI.State<Value>

enum RosePine {
    static let base = color(0x232136)
    static let surface = color(0x2a273f)
    static let overlay = color(0x393552)
    static let muted = color(0x6e6a86)
    static let subtle = color(0x908caa)
    static let text = color(0xe0def4)
    static let love = color(0xeb6f92)
    static let gold = color(0xf6c177)
    static let rose = color(0xea9a97)
    static let pine = color(0x3e8fb0)
    static let foam = color(0x9ccfd8)
    static let iris = color(0xc4a7e7)
    static let highlightLow = color(0x2a283e)
    static let highlightMed = color(0x44415a)
    static let highlightHigh = color(0x56526e)

    private static func color(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255
        )
    }
}

@MainActor
struct MenuContent: View {
    @ObservedObject var store: AppStore
    @ViewState private var filter: PullRequestFilter = .open
    @ViewState private var showsRepositories: Bool
    @ViewState private var repositorySearch = ""
    @ViewState private var copyToastID: UUID?
    @Namespace private var filterSelection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(store: AppStore) {
        self.store = store
        _showsRepositories = ViewState(initialValue: store.selectedRepositories.isEmpty)
    }

    private var allPullRequests: [PullRequest] {
        store.stacks.flatMap(\.pullRequests)
    }

    private var visibleStacks: [VisibleStack] {
        store.stacks.compactMap { stack in
            let requests = stack.pullRequests.filter { filter.includes($0) }
            guard !requests.isEmpty else { return nil }
            return VisibleStack(stack: stack, requests: requests)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsRepositories {
                repositorySettings
            } else {
                filterBar
                Divider().overlay(RosePine.highlightMed)
                content
            }
            Divider().overlay(RosePine.highlightMed)
            footer
        }
        .padding(.top, 12)
        .frame(
            width: 440,
            height: min(1_000, (NSScreen.main?.visibleFrame.height ?? 1_032) - 32)
        )
        .foregroundStyle(RosePine.text)
        .tint(RosePine.pine)
        .background(RosePine.base)
        .overlay(alignment: .bottom) {
            if copyToastID != nil {
                Label("Copied stack", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(RosePine.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RosePine.overlay, in: Capsule())
                    .overlay(Capsule().strokeBorder(RosePine.highlightHigh, lineWidth: 1))
                    .shadow(color: RosePine.base.opacity(0.5), radius: 6, y: 2)
                    .padding(.bottom, 54)
                    .allowsHitTesting(false)
            }
        }
        .preferredColorScheme(.dark)
        .task(id: copyToastID) {
            guard let id = copyToastID else { return }
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
            if copyToastID == id { copyToastID = nil }
        }
        .onDisappear { copyToastID = nil }
    }

    private func showCopyToast() {
        copyToastID = UUID()
        AccessibilityNotification.Announcement("Copied stack").post()
    }

    private var filterBar: some View {
        let requests = allPullRequests
        var counts: [PullRequestFilter: Int] = [.all: requests.count]
        for request in requests {
            let category: PullRequestFilter = request.state == "MERGED"
                ? .merged : (request.isDraft ? .draft : .open)
            counts[category, default: 0] += 1
        }
        return HStack(spacing: 3) {
            ForEach(PullRequestFilter.allCases) { item in
                Button {
                    filter = item
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(filter == item ? RosePine.iris : RosePine.subtle)
                        Text(item.rawValue)
                            .font(.system(size: 12, weight: filter == item ? .semibold : .medium))
                        Text(counts[item, default: 0].formatted())
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                filter == item ? RosePine.surface : Color.clear,
                                in: Capsule()
                            )
                    }
                    .foregroundStyle(filter == item ? RosePine.text : RosePine.subtle)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 8)
                    .background {
                        if filter == item {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(RosePine.overlay)
                                .shadow(color: RosePine.text.opacity(0.06), radius: 2, y: 1)
                                .matchedGeometryEffect(id: "selectedFilter", in: filterSelection)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.rawValue), \(counts[item, default: 0]) pull requests")
                .accessibilityAddTraits(filter == item ? .isSelected : [])
                .help(item == .merged
                    ? "Show pull requests merged in the last 24 hours"
                    : "Show \(item.rawValue.lowercased()) pull requests")
            }
        }
        .padding(3)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.86), value: filter)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pull request filter")
        .padding(.horizontal, 18)
        .padding(.bottom, 13)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let error = store.error {
                    errorNotice(error)
                }
                if !store.warnings.isEmpty {
                    warningNotice
                }
                if visibleStacks.isEmpty {
                    emptyState
                } else {
                    LazyVStack(alignment: .leading, spacing: 17) {
                        ForEach(visibleStacks) { group in
                            StackSection(
                                group: group,
                                customName: store.stackNames[group.id],
                                rename: { store.renameStack(group.id, name: $0) },
                                didCopy: showCopyToast,
                                openPR: store.openPR,
                                performAction: { try await store.performAction($0, on: $1) },
                                closePullRequests: store.closePullRequests
                            )
                        }
                    }
                }
            }
            .padding(16)
            .background(AutoHidingScrollbars())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RosePine.highlightLow)
    }

    private func errorNotice(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Couldn't refresh pull requests", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(RosePine.love)
            Text(message)
                .font(.caption)
                .foregroundStyle(RosePine.subtle)
                .lineLimit(4)
                .textSelection(.enabled)
                .help(message)
            HStack {
                if !allPullRequests.isEmpty {
                    Text("Showing the last available results.")
                        .font(.caption2)
                        .foregroundStyle(RosePine.subtle)
                }
                Spacer(minLength: 4)
                Button("Retry", action: refresh)
                    .controlSize(.small)
                    .disabled(store.isRefreshing)
                Button("Copy details") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message, forType: .string)
                }
                .controlSize(.small)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RosePine.love.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
    }

    private var warningNotice: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(store.warnings.enumerated()), id: \.offset) { _, warning in
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(RosePine.subtle)
                        .textSelection(.enabled)
                }
            }
            .padding(.top, 5)
        } label: {
            Label(
                store.warnings.count == 1 ? "1 repository warning" : "\(store.warnings.count) repository warnings",
                systemImage: "exclamationmark.circle"
            )
            .font(.caption)
            .foregroundStyle(RosePine.gold)
        }
        .padding(10)
        .background(RosePine.gold.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
    }

    private var emptyState: some View {
        VStack(spacing: 11) {
            if store.selectedRepositories.isEmpty {
                Image(systemName: "checklist")
                    .font(.system(size: 29, weight: .light))
                    .foregroundStyle(RosePine.subtle)
                Text("Choose your repositories")
                    .font(.system(size: 14, weight: .semibold))
                Text("Select GitHub repositories to see your pull requests. Nothing is fetched until you choose.")
                    .font(.caption)
                    .foregroundStyle(RosePine.subtle)
                    .multilineTextAlignment(.center)
                Button("Choose repositories") { showsRepositories = true }
                    .controlSize(.small)
            } else if store.isRefreshing && allPullRequests.isEmpty {
                ProgressView()
                    .controlSize(.regular)
                Text("Finding your pull requests…")
                    .font(.system(size: 14, weight: .medium))
                Text("Reading your selected GitHub repositories.")
                    .font(.caption)
                    .foregroundStyle(RosePine.subtle)
            } else {
                Image(systemName: store.error == nil ? filter.emptySymbol : "wifi.exclamationmark")
                    .font(.system(size: 29, weight: .light))
                    .foregroundStyle(RosePine.subtle)
                Text(store.error == nil ? filter.emptyTitle : "Pull requests unavailable")
                    .font(.system(size: 14, weight: .semibold))
                Text(store.error == nil ? filter.emptyMessage : "Resolve the refresh error above, then try again.")
                    .font(.caption)
                    .foregroundStyle(RosePine.subtle)
                    .multilineTextAlignment(.center)
                if filter != .all && store.error == nil {
                    Button("Show all pull requests") { filter = .all }
                        .controlSize(.small)
                }
                Button("Choose repositories") { showsRepositories = true }
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 48)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            updateLabel
            Spacer(minLength: 6)
            if store.isRefreshing {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityLabel("Refreshing pull requests")
            }
            Button(action: refresh) {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 23, height: 23)
            }
            .buttonStyle(.borderless)
            .disabled(store.isRefreshing)
            .help("Refresh pull requests (⌘R)")
            .accessibilityLabel("Refresh pull requests")
            .keyboardShortcut("r", modifiers: .command)
            Button {
                showsRepositories.toggle()
            } label: {
                Image(systemName: showsRepositories ? "gearshape.fill" : "gearshape")
                    .frame(width: 23, height: 23)
            }
            .buttonStyle(.borderless)
            .help("Choose GitHub repositories")
            .accessibilityLabel("Choose GitHub repositories")
            .accessibilityValue(showsRepositories ? "Open" : "Closed")
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
                .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private var updateLabel: some View {
        Group {
            if store.isRefreshing {
                Text("Refreshing…")
            } else if let date = store.lastUpdated {
                HStack(spacing: 3) {
                    Text("Updated")
                    Text(date, style: .relative)
                    Text("ago")
                }
                .help(date.formatted(date: .abbreviated, time: .standard))
            } else {
                Text("Not refreshed yet")
            }
        }
        .font(.caption2)
        .foregroundStyle(RosePine.subtle)
        .lineLimit(1)
    }

    private var filteredRepositories: [GitHubRepository] {
        store.availableRepositories.filter { matchesRepositorySearch($0.nameWithOwner) }
    }

    private var unavailableSelectedRepositories: [String] {
        let availableNames = Set(store.availableRepositories.map(\.nameWithOwner))
        return store.selectedRepositories
            .subtracting(availableNames)
            .filter(matchesRepositorySearch)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func matchesRepositorySearch(_ name: String) -> Bool {
        let query = repositorySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || name.localizedCaseInsensitiveContains(query)
    }

    private var repositorySettings: some View {
        let repositories = filteredRepositories
        let unavailable = unavailableSelectedRepositories
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("GitHub repositories")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("Done") { showsRepositories = false }
                    .controlSize(.small)
            }
            Text("Choose where to look for your pull requests. Changes are saved and refresh automatically.")
                .font(.caption)
                .foregroundStyle(RosePine.subtle)
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(RosePine.subtle)
                TextField("Search repositories", text: $repositorySearch)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Search GitHub repositories")
                if !repositorySearch.isEmpty {
                    Button {
                        repositorySearch = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(RosePine.subtle)
                    .help("Clear search")
                    .accessibilityLabel("Clear repository search")
                }
            }
            .padding(8)
            .background(RosePine.overlay, in: RoundedRectangle(cornerRadius: 7))
            HStack {
                Text("\(store.selectedRepositories.count) selected")
                    .font(.caption)
                    .foregroundStyle(RosePine.subtle)
                Spacer()
                if store.isLoadingRepositories {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Loading GitHub repositories")
                }
                Button {
                    Task { await store.loadRepositories(force: true) }
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(store.isLoadingRepositories)
                .help("Reload repositories accessible to your GitHub account")
            }
            if let error = store.repositoryError {
                repositoryErrorNotice(error)
            }
            Divider().overlay(RosePine.highlightMed)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if !unavailable.isEmpty {
                        Text("Selected · not in loaded list")
                            .font(.caption)
                            .foregroundStyle(RosePine.subtle)
                        ForEach(unavailable, id: \.self) { name in
                            repositoryRow(name, isPrivate: false, unavailable: true)
                        }
                        Text("You can still deselect these repositories to stop tracking them.")
                            .font(.caption2)
                            .foregroundStyle(RosePine.subtle)
                        Divider().overlay(RosePine.highlightMed)
                    }
                    ForEach(repositories) { repository in
                        repositoryRow(repository.nameWithOwner, isPrivate: repository.isPrivate)
                    }
                    if repositories.isEmpty && unavailable.isEmpty {
                        repositoryListEmptyState
                    }
                }
                .padding(.vertical, 4)
                .background(AutoHidingScrollbars())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await store.loadRepositories() }
    }

    private func repositoryRow(_ name: String, isPrivate: Bool, unavailable: Bool = false) -> some View {
        Toggle(isOn: Binding(
            get: { store.selectedRepositories.contains(name) },
            set: { store.setRepository(name, selected: $0) }
        )) {
            HStack(spacing: 6) {
                Text(name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(name)
                if isPrivate {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(RosePine.subtle)
                        .help("Private repository")
                        .accessibilityLabel("Private repository")
                }
                Spacer(minLength: 0)
                if unavailable {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(RosePine.subtle)
                        .help("Not in the loaded repository list")
                }
            }
        }
        .toggleStyle(.checkbox)
        .padding(.vertical, 3)
        .accessibilityLabel(name)
    }

    private func repositoryErrorNotice(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Couldn't load repositories", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(RosePine.love)
            Text(message)
                .font(.caption)
                .foregroundStyle(RosePine.subtle)
                .lineLimit(4)
                .textSelection(.enabled)
                .help(message)
            Button("Retry") {
                Task { await store.loadRepositories(force: true) }
            }
            .controlSize(.small)
            .disabled(store.isLoadingRepositories)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RosePine.love.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
    }

    private var repositoryListEmptyState: some View {
        VStack(spacing: 9) {
            if store.isLoadingRepositories {
                Text("Loading GitHub repositories…")
                    .font(.system(size: 13, weight: .medium))
                Text("Finding repositories accessible to your signed-in GitHub account.")
                    .font(.caption)
                    .foregroundStyle(RosePine.subtle)
            } else if !repositorySearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Image(systemName: "magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(RosePine.subtle)
                Text("No matching repositories")
                    .font(.system(size: 13, weight: .medium))
                Text("Try a different owner or repository name.")
                    .font(.caption)
                    .foregroundStyle(RosePine.subtle)
                Button("Clear search") { repositorySearch = "" }
                    .controlSize(.small)
            } else if store.repositoryError == nil {
                Image(systemName: "tray")
                    .font(.title2)
                    .foregroundStyle(RosePine.subtle)
                Text("No repositories available")
                    .font(.system(size: 13, weight: .medium))
                Text("No accessible repositories were returned for your GitHub account. Check your GitHub access, then reload.")
                    .font(.caption)
                    .foregroundStyle(RosePine.subtle)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 28)
    }

    private func refresh() {
        Task { await store.refresh() }
    }
}

private struct AutoHidingScrollbars: NSViewRepresentable {
    func makeNSView(context: Context) -> ConfigurationView { ConfigurationView() }

    func updateNSView(_ nsView: ConfigurationView, context: Context) {
        nsView.configure()
    }

    final class ConfigurationView: NSView {
        private var configurationScheduled = false
        private weak var observedScrollView: NSScrollView?
        private var styleObservation: NSKeyValueObservation?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configure()
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func configure() {
            guard !configurationScheduled else { return }
            configurationScheduled = true
            // SwiftUI applies its system scroller style during the current update.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.configurationScheduled = false
                guard let scrollView = self.enclosingScrollView else { return }
                if self.observedScrollView !== scrollView {
                    self.observedScrollView = scrollView
                    self.styleObservation = scrollView.observe(\.scrollerStyle) { [weak self] scrollView, _ in
                        if scrollView.scrollerStyle != .overlay { self?.configure() }
                    }
                }
                if scrollView.scrollerStyle != .overlay {
                    scrollView.scrollerStyle = .overlay
                }
                if !scrollView.autohidesScrollers {
                    scrollView.autohidesScrollers = true
                }
            }
        }
    }
}

private enum PullRequestFilter: String, CaseIterable, Identifiable {
    case open = "Open"
    case draft = "Drafts"
    case merged = "Merged"
    case all = "All"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .open: return "arrow.triangle.pull"
        case .draft: return "pencil.circle"
        case .merged: return "arrow.triangle.merge"
        case .all: return "tray.full"
        }
    }

    func includes(_ request: PullRequest) -> Bool {
        switch self {
        case .all: return true
        case .open: return request.state == "OPEN" && !request.isDraft
        case .draft: return request.state == "OPEN" && request.isDraft
        case .merged: return request.state == "MERGED"
        }
    }

    var emptySymbol: String {
        switch self {
        case .all, .open: return "tray"
        case .draft: return "pencil.circle"
        case .merged: return "arrow.triangle.merge"
        }
    }

    var emptyTitle: String {
        switch self {
        case .all: return "You're all caught up"
        case .open: return "No open pull requests"
        case .draft: return "No drafts in progress"
        case .merged: return "No recent merges"
        }
    }

    var emptyMessage: String {
        switch self {
        case .all: return "Your open pull requests and merges from the last 24 hours will appear here."
        case .open: return "Ready-for-review pull requests will appear here. Drafts have their own filter."
        case .draft: return "Pull requests marked as drafts will appear here."
        case .merged: return "Pull requests merged in the last 24 hours will appear here."
        }
    }
}

private struct VisibleStack: Identifiable {
    let stack: PRStack
    let requests: [PullRequest]
    private let depths: [Int]
    private let continuationMasks: [Int]

    var id: String { stack.id }

    init(stack: PRStack, requests: [PullRequest]) {
        self.stack = stack
        self.requests = requests
        let visibleIDs = Set(requests.map(\.id))
        var visibleAncestorDepths: [Int] = []
        var rowDepths: [Int] = []
        for request in stack.pullRequests {
            let originalDepth = stack.depths[request.id] ?? 0
            while let last = visibleAncestorDepths.last, last >= originalDepth {
                visibleAncestorDepths.removeLast()
            }
            if visibleIDs.contains(request.id) {
                rowDepths.append(min(visibleAncestorDepths.count, 3))
                visibleAncestorDepths.append(originalDepth)
            }
        }
        depths = rowDepths

        // The nearest following row at or above a column determines its rail.
        var nextDepths: [Int?] = Array(repeating: nil, count: 4)
        var masks = Array(repeating: 0, count: rowDepths.count)
        for index in rowDepths.indices.reversed() {
            let depth = rowDepths[index]
            for column in 1...3 {
                if column <= depth && nextDepths[column] == column {
                    masks[index] |= 1 << column
                }
                if depth <= column {
                    nextDepths[column] = depth
                }
            }
        }
        continuationMasks = masks
    }

    func depth(at index: Int) -> Int { depths[index] }
    func continuationMask(after index: Int) -> Int { continuationMasks[index] }
}


@MainActor
private struct StackSection: View {
    let group: VisibleStack
    let customName: String?
    let rename: (String) -> Void
    let didCopy: () -> Void
    let openPR: (PullRequest) -> Void
    let performAction: (PRAction, PullRequest) async throws -> Void
    let closePullRequests: ([PullRequest]) async throws -> Void
    @ViewState private var isRenaming = false

    private var displayName: String { customName ?? group.stack.name }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if group.stack.pullRequests.count > 1 {
                sectionHeader
            }
            VStack(spacing: 0) {
                ForEach(Array(group.requests.enumerated()), id: \.element.id) { index, request in
                    PullRequestCard(
                        request: request,
                        open: { openPR(request) },
                        performAction: { try await performAction($0, request) },
                        dependents: group.stack.openDescendants(above: request.id),
                        closePullRequests: closePullRequests
                    )
                    .padding(.bottom, index == group.requests.count - 1 ? 0 : 6)
                    .padding(.leading, CGFloat(group.depth(at: index)) * 12)
                    .overlay(alignment: .leading) {
                        if group.depth(at: index) > 0 {
                            StackConnector(
                                depth: group.depth(at: index),
                                continuationMask: group.continuationMask(after: index)
                            )
                            .allowsHitTesting(false)
                        }
                    }
                }
            }
        }
        .onDisappear { isRenaming = false }
    }

    private var sectionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "rectangle.stack.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(RosePine.iris)
                .frame(width: 18)
            if isRenaming {
                StackNameEditor(
                    name: displayName,
                    onSave: { name in
                        rename(name)
                        isRenaming = false
                    },
                    onCancel: { isRenaming = false }
                )
                .frame(maxWidth: .infinity)
            } else {
                Text(displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help("\(displayName)\nDouble-click to rename.")
                    .onTapGesture(count: 2) { isRenaming = true }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(named: Text("Rename stack")) { isRenaming = true }
            }
            Text("\(group.requests.count)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(RosePine.subtle)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(RosePine.overlay, in: Capsule())
            Button {
                do {
                    try StackClipboard.copy(group.stack, name: displayName, to: .general)
                    didCopy()
                } catch {
                    NSApp.presentError(error)
                }
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12))
                    .foregroundStyle(RosePine.subtle)
                    .frame(width: 22, height: 22)
            }
            .help("Copy \(displayName) with links (\(group.stack.pullRequests.count) PRs)")
            .accessibilityLabel("Copy stack with links")
            if !isRenaming { Spacer(minLength: 0) }
        }
        .buttonStyle(.borderless)
        .frame(minHeight: 21)
    }

}

private struct StackConnector: View {
    let depth: Int
    let continuationMask: Int

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                for column in 1...depth {
                    let x = CGFloat(column - 1) * 12 + 5
                    let isCurrent = column == depth
                    let extendsBelow = continuationMask & (1 << column) != 0
                    if isCurrent || extendsBelow {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: extendsBelow ? geometry.size.height : 23))
                    }
                    if isCurrent {
                        path.move(to: CGPoint(x: x, y: 23))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: 23))
                    }
                }
            }
            .stroke(RosePine.highlightHigh, style: StrokeStyle(lineWidth: 1))
        }
        .frame(width: CGFloat(depth) * 12)
        .accessibilityHidden(true)
    }
}

@MainActor
private struct PullRequestCard: View {
    let request: PullRequest
    let open: () -> Void
    let performAction: (PRAction) async throws -> Void
    let dependents: [PullRequest]
    let closePullRequests: ([PullRequest]) async throws -> Void
    @ViewState private var pendingAction: PRAction?
    @ViewState private var actionError: String?
    @ViewState private var confirmsClose = false
    @ViewState private var closesDependents = false

    private var mergeActionHelp: String {
        if request.state != "OPEN" { return "Only open PRs can enter the merge queue" }
        if request.isDraft { return "Mark this PR ready for review on GitHub before adding the merge label" }
        if request.hasMergeLabel { return "The merge label is present on GitHub" }
        return "Add the merge label to request the repository's merge queue"
    }

    private var stateColor: Color {
        if request.state == "MERGED" { return RosePine.iris }
        return request.isDraft ? RosePine.subtle : RosePine.pine
    }

    private var stateTitle: String {
        if request.state == "MERGED" { return "Merged" }
        return request.isDraft ? "Draft" : "Open"
    }

    private var review: StatusDescription? {
        switch request.reviewDecision {
        case "APPROVED": return StatusDescription(title: "Approved", symbol: "checkmark.seal.fill", color: RosePine.pine)
        case "CHANGES_REQUESTED": return StatusDescription(title: "Changes requested", symbol: "exclamationmark.bubble.fill", color: RosePine.gold)
        case "REVIEW_REQUIRED": return StatusDescription(title: "Needs review", symbol: "person.crop.circle.badge.clock", color: RosePine.subtle)
        default: return nil
        }
    }

    private var checks: StatusDescription? {
        switch request.checks {
        case "SUCCESS": return StatusDescription(title: "Checks passed", symbol: "checkmark.circle.fill", color: RosePine.pine)
        case "FAILURE": return StatusDescription(title: "Checks failed", symbol: "xmark.circle.fill", color: RosePine.love)
        case "ERROR": return StatusDescription(title: "Check error", symbol: "exclamationmark.circle.fill", color: RosePine.love)
        case "PENDING": return StatusDescription(title: "Checks running", symbol: "clock", color: RosePine.gold)
        case "EXPECTED": return StatusDescription(title: "Checks queued", symbol: "clock.badge.questionmark", color: RosePine.subtle)
        default: return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                metadata
                Text(request.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(RosePine.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            statusLine
            if confirmsClose {
                closeConfirmation
            }
            if let actionError {
                Label(actionError, systemImage: "exclamationmark.circle")
                    .font(.caption2)
                    .foregroundStyle(RosePine.love)
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .help(actionError)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 9)
                .fill(RosePine.surface)
                .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(RosePine.highlightMed, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }


    private var closeConfirmation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(RosePine.highlightMed)
            Text("Close this pull request?")
                .font(.system(size: 12, weight: .semibold))
            Text("This won't merge any PRs or delete their branches.")
                .font(.caption2)
                .foregroundStyle(RosePine.subtle)
            if !dependents.isEmpty {
                Toggle("Also close \(dependents.count) \(dependents.count == 1 ? "PR" : "PRs") above this one", isOn: $closesDependents)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                if closesDependents {
                    Text("Above: " + dependents.reversed().map { "#\($0.number)" }.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(RosePine.subtle)
                        .lineLimit(3)
                        .help(dependents.reversed().map { "\($0.repository)#\($0.number): \($0.title)" }.joined(separator: "\n"))
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { confirmsClose = false }
                Button(closesDependents ? "Close \(dependents.count + 1) PRs" : "Close PR", role: .destructive) {
                    run(.close)
                }
                    .tint(RosePine.love)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .onExitCommand { confirmsClose = false }
    }

    private var metadata: some View {
        HStack(spacing: 6) {
            Text(verbatim: "\(request.repository) #\(request.number)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(RosePine.subtle)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 2)
            HStack(spacing: 3) {
                Circle().fill(stateColor).frame(width: 4, height: 4)
                Text(stateTitle)
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(stateColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(stateColor.opacity(0.09), in: Capsule())
        }
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                statusLabels(compact: false)
                statusLabels(compact: true)
            }
            Spacer(minLength: 1)
            if pendingAction != nil {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityLabel("Updating pull request")
            }
            Button(action: open) {
                GitHubMark()
                    .fill(RosePine.subtle)
                    .frame(width: 14, height: 14)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Open \(request.repository)#\(String(request.number)) on GitHub")
            .accessibilityLabel("Open \(request.repository)#\(String(request.number)) on GitHub")
            .contextMenu {
                Button("Open pull request", systemImage: "arrow.up.right.square", action: open)
                Divider()
                Button("Copy pull request URL", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(request.url.absoluteString, forType: .string)
                }
            }
            if request.state != "MERGED" {
                Button { run(.addMergeLabel) } label: {
                    Image(systemName: "arrow.triangle.merge")
                        .foregroundStyle(request.hasMergeLabel ? RosePine.pine : RosePine.subtle)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .help(mergeActionHelp)
                .accessibilityLabel("Add merge label")
                .disabled(request.state != "OPEN" || request.isDraft || pendingAction != nil || request.hasMergeLabel || confirmsClose)
                Button {
                    closesDependents = false
                    confirmsClose = true
                } label: {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(RosePine.subtle)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .help("Close pull request…")
                .accessibilityLabel("Close pull request")
                .disabled(request.state != "OPEN" || pendingAction != nil || confirmsClose)
            }
        }
    }

    private func run(_ action: PRAction) {
        guard pendingAction == nil else { return }
        let closeTargets = closesDependents ? dependents + [request] : [request]
        confirmsClose = false
        pendingAction = action
        actionError = nil
        Task {
            defer { pendingAction = nil }
            do {
                if action == .close {
                    try await closePullRequests(closeTargets)
                } else {
                    try await performAction(action)
                }
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    private func statusLabels(compact: Bool) -> some View {
        HStack(spacing: 9) {
            if let review {
                StatusLabel(status: review, compact: compact)
            }
            if let checks {
                StatusLabel(status: checks, compact: compact)
            }
            if review == nil && checks == nil {
                Text("No review or check status")
                    .font(.system(size: 9))
                    .foregroundStyle(RosePine.muted)
                    .lineLimit(1)
            }
        }
    }
}

private struct StatusDescription {
    let title: String
    let symbol: String
    let color: Color
}

private struct StatusLabel: View {
    let status: StatusDescription
    let compact: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: status.symbol)
                .foregroundStyle(status.color)
            if !compact {
                Text(status.title)
                    .foregroundStyle(RosePine.subtle)
                    .fixedSize()
            }
        }
        .font(.system(size: 9))
        .help(status.title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.title)
    }
}
