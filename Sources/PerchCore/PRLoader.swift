import Foundation

public enum PRLoader {
    public static func load(repositories: [String]) async throws -> Snapshot {
        guard !repositories.isEmpty else { return Snapshot(pullRequests: [], warnings: []) }
        // Subprocess waits must never execute on the UI actor.
        let work = Task.detached(priority: .utility) {
            let gh = try GitHubClient.findExecutable()
            let pullRequests = try GitHubClient(executable: gh, runner: ProcessRunner())
                .load(repositories: repositories, now: Date())
            try Task.checkCancellation()
            return Snapshot(pullRequests: pullRequests, warnings: [])
        }
        return try await withTaskCancellationHandler(operation: {
            try await work.value
        }, onCancel: {
            work.cancel()
        })
    }

    public static func repositories() async throws -> [GitHubRepository] {
        let work = Task.detached(priority: .utility) {
            let gh = try GitHubClient.findExecutable()
            return try GitHubClient(executable: gh, runner: ProcessRunner()).repositories()
        }
        return try await withTaskCancellationHandler(operation: {
            try await work.value
        }, onCancel: {
            work.cancel()
        })
    }
}

struct GitHubClient {
    let executable: URL
    let runner: CommandRunning

    static func findExecutable(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> URL {
        let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
            + (environment["PATH"] ?? "").split(separator: ":").map { String($0) + "/gh" }
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        throw BackendError.message("GitHub CLI (gh) was not found. Install it with ‘brew install gh’, then run ‘gh auth login’.")
    }

    func repositories() throws -> [GitHubRepository] {
        var repositories: [String: GitHubRepository] = [:]
        var cursor: String?
        var cursors = Set<String>()
        while true {
            let data: RepositoryData = try request(Self.repositoriesQuery, variables: cursor.map { ["cursor": $0] } ?? [:])
            guard let connection = data.viewer?.repositories else {
                throw BackendError.message("GitHub returned no repository catalog. Check ‘gh auth status’ and the account’s repository access.")
            }
            for repository in connection.nodes {
                repositories[repository.nameWithOwner] = repository
            }
            guard connection.pageInfo.hasNextPage else { break }
            cursor = try connection.pageInfo.nextCursor(seen: &cursors)
        }
        return repositories.values.sorted {
            $0.nameWithOwner.localizedStandardCompare($1.nameWithOwner) == .orderedAscending
        }
    }

    func load(repositories: [String], now: Date) throws -> [PullRequest] {
        guard !repositories.isEmpty else { return [] }
        let data: ViewerData = try request("query { viewer { login } }")
        guard let login = data.viewer?.login, !login.isEmpty else {
            throw BackendError.message("GitHub returned no viewer. Check ‘gh auth status’ and the account’s repository access.")
        }
        let cutoff = now.addingTimeInterval(-24 * 60 * 60)
        let timestamp = ISO8601DateFormatter().string(from: cutoff)
        var results: [PullRequest] = []
        var seen = Set<String>()
        for repository in Set(repositories).sorted() {
            for state in ["OPEN", "MERGED"] {
                // Search scopes both repository and author on GitHub; never fetch
                // the viewer's global PR feed and then filter it locally.
                let stateFilter = state == "OPEN" ? "is:open" : "is:merged merged:>=\(timestamp)"
                let search = "repo:\(repository) author:\(login) is:pr \(stateFilter) sort:updated-desc"
                var cursor: String?
                var cursors = Set<String>()
                var fetched = 0
                while true {
                    var variables = ["search": search]
                    if let cursor { variables["cursor"] = cursor }
                    let data: SearchData = try request(Self.pullRequestsQuery, variables: variables)
                    guard let connection = data.search else {
                        throw BackendError.message("GitHub returned no pull request results for \(repository).")
                    }
                    fetched += connection.nodes.count
                    // GitHub search exposes at most 1,000 results. Fail explicitly
                    // rather than presenting a silently truncated repository.
                    guard connection.issueCount <= 1_000,
                          !(connection.pageInfo.hasNextPage && fetched >= 1_000) else {
                        throw BackendError.message("GitHub search is limited to 1,000 results for \(repository) (\(state.lowercased()) pull requests authored by \(login)). Perch cannot load this repository completely. Deselect it to load the other repositories; no truncated result was returned.")
                    }
                    for node in connection.nodes {
                        let pr = node.pullRequest
                        if pr.state == "OPEN" || (pr.state == "MERGED" && pr.mergedAt.map { $0 >= cutoff } == true) {
                            if seen.insert(pr.id).inserted { results.append(pr) }
                        }
                    }
                    guard connection.pageInfo.hasNextPage else { break }
                    cursor = try connection.pageInfo.nextCursor(seen: &cursors)
                }
            }
        }
        return results.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
    }

    private func request<Response: Decodable>(_ query: String, variables: [String: String] = [:]) throws -> Response {
        try Task.checkCancellation()
        var arguments = ["api", "graphql", "-f", "query=\(query)"]
        for key in variables.keys.sorted() {
            arguments += ["-f", "\(key)=\(variables[key]!)"]
        }
        let result = try runner.run(executable: executable, arguments: arguments, timeout: 60)
        guard result.status == 0 else {
            let detail = result.errorText.isEmpty ? "GitHub CLI exited with status \(result.status)." : result.errorText
            throw BackendError.message("Could not load GitHub data. \(detail)\nCheck ‘gh auth status’ or run ‘gh auth login’.")
        }
        // Decode errors separately so partial/invalid data cannot hide an API error.
        let errors: GraphQLErrors
        do {
            errors = try JSONDecoder().decode(GraphQLErrors.self, from: result.output)
        } catch {
            throw BackendError.message("GitHub returned an unreadable response: \(error.localizedDescription)")
        }
        if let errors = errors.errors, !errors.isEmpty {
            throw BackendError.message("GitHub could not load data: " + errors.map(\.message).joined(separator: "; "))
        }
        do {
            let response = try Self.decoder().decode(GraphQLResponse<Response>.self, from: result.output)
            guard let data = response.data else {
                throw BackendError.message("GitHub returned no data. Check ‘gh auth status’ and the account’s repository access.")
            }
            return data
        } catch let error as BackendError {
            throw error
        } catch {
            throw BackendError.message("GitHub returned an unreadable response: \(error.localizedDescription)")
        }
    }

    private static let repositoriesQuery = """
    query($cursor: String) {
      viewer {
        repositories(first: 100, after: $cursor, affiliations: [OWNER, COLLABORATOR, ORGANIZATION_MEMBER], ownerAffiliations: [OWNER, COLLABORATOR, ORGANIZATION_MEMBER], orderBy: {field: NAME, direction: ASC}) {
          nodes { nameWithOwner isPrivate }
          pageInfo { hasNextPage endCursor }
        }
      }
    }
    """

    private static let pullRequestsQuery = """
    query($search: String!, $cursor: String) {
      search(query: $search, type: ISSUE, first: 100, after: $cursor) {
        issueCount
        nodes {
          ... on PullRequest {
            number title url state isDraft mergedAt updatedAt headRefName baseRefName reviewDecision
            repository { nameWithOwner }
            headRepository { nameWithOwner }
            labels(first: 100) { nodes { name } }
            commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
          }
        }
        pageInfo { hasNextPage endCursor }
      }
    }
    """

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let wholeSeconds = ISO8601DateFormatter()
        wholeSeconds.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = fractional.date(from: value) ?? wholeSeconds.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid GitHub timestamp: \(value)")
        }
        return decoder
    }
}

private struct GraphQLResponse<Data: Decodable>: Decodable { let data: Data? }
private struct GraphQLErrors: Decodable {
    let errors: [GraphQLError]?
    struct GraphQLError: Decodable { let message: String }
}
private struct ViewerData: Decodable {
    let viewer: Viewer?
    struct Viewer: Decodable { let login: String }
}
private struct RepositoryData: Decodable {
    let viewer: Viewer?
    struct Viewer: Decodable { let repositories: RepositoryConnection }
    struct RepositoryConnection: Decodable {
        let nodes: [GitHubRepository]
        let pageInfo: PageInfo
    }
}
private struct SearchData: Decodable {
    let search: Connection?
    struct Connection: Decodable {
        let issueCount: Int
        let nodes: [PRNode]
        let pageInfo: PageInfo
    }
}
private struct PageInfo: Decodable {
    let hasNextPage: Bool
    let endCursor: String?

    func nextCursor(seen: inout Set<String>) throws -> String {
        guard let cursor = endCursor, !cursor.isEmpty, seen.insert(cursor).inserted else {
            throw BackendError.message("GitHub returned a repeated or missing pagination cursor; refresh to try again.")
        }
        return cursor
    }
}

private struct PRNode: Decodable {
    let number: Int
    let title: String
    let url: URL
    let state: String
    let isDraft: Bool
    let mergedAt: Date?
    let updatedAt: Date
    let headRefName: String
    let baseRefName: String
    let reviewDecision: String?
    let repository: Repository
    let headRepository: Repository?
    let commits: Commits
    let labels: Labels

    struct Repository: Decodable { let nameWithOwner: String }
    struct Commits: Decodable { let nodes: [Node] }
    struct Node: Decodable { let commit: Commit }
    struct Commit: Decodable { let statusCheckRollup: Rollup? }
    struct Rollup: Decodable { let state: String }
    struct Labels: Decodable {
        let nodes: [Label]
        struct Label: Decodable { let name: String }
    }

    var pullRequest: PullRequest {
        PullRequest(number: number, title: title, url: url,
                    repository: repository.nameWithOwner, headRepository: headRepository?.nameWithOwner,
                    headBranch: headRefName, baseBranch: baseRefName, isDraft: isDraft,
                    state: state, mergedAt: mergedAt, updatedAt: updatedAt,
                    reviewDecision: reviewDecision, checks: commits.nodes.last?.commit.statusCheckRollup?.state,
                    hasMergeLabel: labels.nodes.contains { $0.name.caseInsensitiveCompare("merge") == .orderedSame })
    }
}
