import AppKit
import Combine
import PerchCore

@MainActor
final class AppStore: ObservableObject {
    @Published var pullRequests: [PullRequest] = []
    @Published var isRefreshing = false
    @Published var lastUpdated: Date?
    @Published var error: String?
    @Published var warnings: [String] = []
    @Published private(set) var selectedRepositories: Set<String> {
        didSet { defaults.set(selectedRepositories.sorted(), forKey: "selectedRepositories") }
    }
    @Published var availableRepositories: [GitHubRepository] = []
    @Published var isLoadingRepositories = false
    @Published var repositoryError: String?
    @Published var stackNames: [String: String] {
        didSet { defaults.set(stackNames, forKey: "stackNames") }
    }
    private let defaults: UserDefaults
    private let performPRAction: (PRAction, PullRequest) async throws -> Void
    private var timer: AnyCancellable?
    private var workspaceObserver: AnyCancellable?

    private var refreshAgain = false
    private var hasLoadedRepositories = false
    private var activeLoad: Task<Snapshot, Error>?
    private var mutationGeneration = 0
    private var isClosingPRs = false
    init(
        defaults: UserDefaults = .standard,
        performPRAction: @escaping (PRAction, PullRequest) async throws -> Void = {
            try await PRActions.perform($0, on: $1)
        }
    ) {
        self.defaults = defaults
        self.performPRAction = performPRAction
        selectedRepositories = Set(defaults.stringArray(forKey: "selectedRepositories") ?? [])
        defaults.removeObject(forKey: "repositoryRoots")
        stackNames = defaults.dictionary(forKey: "stackNames") as? [String: String] ?? [:]
        timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            Task { await self?.refresh() }
        }
        workspaceObserver = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in Task { await self?.refresh() } }
        Task { await refresh() }
    }

    var stacks: [PRStack] {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        return StackBuilder.group(pullRequests.filter {
            $0.state == "OPEN" || ($0.state == "MERGED" && ($0.mergedAt.map { $0 >= cutoff } ?? false))
        })
    }

    func refresh() async {
        guard !isClosingPRs else {
            refreshAgain = true
            return
        }
        guard !isRefreshing else {
            refreshAgain = true
            return
        }
        isRefreshing = true
        defer {
            isRefreshing = false
            if refreshAgain {
                refreshAgain = false
                Task { await refresh() }
            }
        }
        let selection = selectedRepositories
        let generation = mutationGeneration
        guard !selection.isEmpty else {
            pullRequests = []
            warnings = []
            error = nil
            lastUpdated = nil
            return
        }
        let load = Task { try await PRLoader.load(repositories: selection.sorted()) }
        activeLoad = load
        defer { activeLoad = nil }
        do {
            let snapshot = try await load.value
            guard selectedRepositories == selection, mutationGeneration == generation else { return }
            pullRequests = snapshot.pullRequests
            warnings = snapshot.warnings
            error = nil
            lastUpdated = Date()
        } catch is CancellationError {
            // Selection changes cancel the previous repository scope.
        } catch {
            guard selectedRepositories == selection, mutationGeneration == generation else { return }
            self.error = error.localizedDescription
        }
    }

    func loadRepositories(force: Bool = false) async {
        guard !isLoadingRepositories, force || !hasLoadedRepositories else { return }
        isLoadingRepositories = true
        defer { isLoadingRepositories = false }
        do {
            availableRepositories = try await PRLoader.repositories()
            repositoryError = nil
            hasLoadedRepositories = true
        } catch {
            repositoryError = error.localizedDescription
        }
    }

    func setRepository(_ name: String, selected: Bool) {
        let changed: Bool
        if selected { changed = selectedRepositories.insert(name).inserted }
        else { changed = selectedRepositories.remove(name) != nil }
        guard changed else { return }
        activeLoad?.cancel()
        pullRequests.removeAll { !selectedRepositories.contains($0.repository) }
        error = nil
        warnings = []
        lastUpdated = nil
        Task { await refresh() }
    }

    func renameStack(_ id: String, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { stackNames.removeValue(forKey: id) }
        else { stackNames[id] = trimmed }
    }

    func performAction(_ action: PRAction, on pr: PullRequest) async throws {
        if action == .close {
            try await closePullRequests([pr])
            return
        }
        try await performPRAction(action, pr)
        mutationGeneration += 1
        activeLoad?.cancel()
        if let index = pullRequests.firstIndex(where: { $0.id == pr.id }) {
            // The action client has read the label back from GitHub.
            pullRequests[index].hasMergeLabel = true
        }
        Task {
            await refresh()
            // Queue automation may remove a label shortly after accepting it.
            try? await Task.sleep(for: .seconds(8))
            await refresh()
        }
    }

    func closePullRequests(_ requests: [PullRequest]) async throws {
        guard !requests.isEmpty else { return }
        guard !isClosingPRs else {
            throw NSError(domain: "Perch", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Another close operation is in progress. Wait for it to finish."
            ])
        }
        isClosingPRs = true
        mutationGeneration += 1
        activeLoad?.cancel()
        defer {
            isClosingPRs = false
            refreshAgain = false
            Task { await refresh() }
        }
        var completed = 0
        for pr in requests {
            do {
                try await performPRAction(.close, pr)
                completed += 1
                pullRequests.removeAll { $0.id == pr.id }
            } catch {
                guard requests.count > 1 else { throw error }
                throw NSError(domain: "Perch", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Closed \(completed) of \(requests.count) PRs. Stopped at \(pr.repository)#\(pr.number); remaining PRs were not closed. \(error.localizedDescription)"
                ])
            }
        }
    }

    func openPR(_ pr: PullRequest) { NSWorkspace.shared.open(pr.url) }

}

@MainActor
final class PerchAppDelegate: NSObject, NSApplicationDelegate {
    let store = AppStore()
    private var popoverController: MenuPopoverController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        popoverController = MenuPopoverController(store: store)
    }
}

@main
enum PerchApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let menu = NSMenu()
        let appMenu = NSMenu(title: "Perch")
        appMenu.addItem(withTitle: "Quit Perch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(withTitle: "Perch", action: nil, keyEquivalent: "").submenu = appMenu

        // Hosting SwiftUI in AppKit does not install the standard editing commands.
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        menu.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = editMenu
        application.mainMenu = menu

        let delegate = PerchAppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
