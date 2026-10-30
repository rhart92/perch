import Foundation

public struct PullRequest: Identifiable, Codable, Sendable {
    public var id: String { url.absoluteString }
    public let number: Int
    public let title: String
    public let url: URL
    public let repository: String
    public let headRepository: String?
    public let headBranch: String
    public let baseBranch: String
    public let isDraft: Bool
    public let state: String
    public let mergedAt: Date?
    public let updatedAt: Date
    public let reviewDecision: String?
    public let checks: String?
    public var hasMergeLabel: Bool

    public init(number: Int, title: String, url: URL, repository: String,
                headRepository: String?, headBranch: String, baseBranch: String,
                isDraft: Bool, state: String, mergedAt: Date?, updatedAt: Date,
                reviewDecision: String?, checks: String?, hasMergeLabel: Bool = false) {
        self.number = number
        self.title = title
        self.url = url
        self.repository = repository
        self.headRepository = headRepository
        self.headBranch = headBranch
        self.baseBranch = baseBranch
        self.isDraft = isDraft
        self.state = state
        self.mergedAt = mergedAt
        self.updatedAt = updatedAt
        self.reviewDecision = reviewDecision
        self.checks = checks
        self.hasMergeLabel = hasMergeLabel
    }
}

public struct GitHubRepository: Identifiable, Codable, Sendable, Equatable {
    public var id: String { nameWithOwner }
    public let nameWithOwner: String
    public let isPrivate: Bool

    public init(nameWithOwner: String, isPrivate: Bool) {
        self.nameWithOwner = nameWithOwner
        self.isPrivate = isPrivate
    }
}

public struct PRStack: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let pullRequests: [PullRequest]
    public let depths: [String: Int]
    public let updatedAt: Date

    public init(id: String, name: String, pullRequests: [PullRequest], depths: [String: Int]) {
        self.id = id
        self.name = name
        self.pullRequests = pullRequests
        self.depths = depths
        self.updatedAt = pullRequests.lazy.map(\.updatedAt).max() ?? .distantPast
    }

    /// Open descendants in leaf-first order, using the full unfiltered stack.
    public func openDescendants(above id: String) -> [PullRequest] {
        guard let index = pullRequests.firstIndex(where: { $0.id == id }),
              let depth = depths[id] else { return [] }
        var end = index + 1
        while end < pullRequests.count, (depths[pullRequests[end].id] ?? 0) > depth {
            end += 1
        }
        return pullRequests[(index + 1)..<end].reversed().filter { $0.state == "OPEN" }
    }
}

public struct Snapshot: Sendable {
    public let pullRequests: [PullRequest]
    public let warnings: [String]

    public init(pullRequests: [PullRequest], warnings: [String]) {
        self.pullRequests = pullRequests
        self.warnings = warnings
    }
}
