import Foundation
import Testing
@testable import PerchCore

struct PRLoaderTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func testEmptySelectionDoesNotRunAnyCommands() async throws {
        let runner = StubRunner()
        let prs = try GitHubClient(executable: gh, runner: runner).load(repositories: [], now: now)
        #expect(prs.isEmpty)
        #expect(runner.calls.isEmpty)
        // The public entry point also succeeds without looking up gh or logging in.
        let snapshot = try await PRLoader.load(repositories: [])
        #expect(snapshot.pullRequests.isEmpty)
        #expect(snapshot.warnings.isEmpty)
    }

    @Test func testQueriesOnlySelectedRepositoriesAndAuthenticatedAuthor() throws {
        let runner = StubRunner()
        var requestedRepositories = Set<String>()
        var requestedStates = Set<String>()
        runner.handler = { arguments in
            let variables = self.variables(arguments)
            guard let search = variables["search"] else { return self.viewer(login: "signed-in-user") }
            let qualifiers = Set(search.split(separator: " ").map(String.init))
            #expect(qualifiers.contains("author:signed-in-user"))
            #expect(qualifiers.contains("is:pr"))
            let repository = try #require(qualifiers.first { $0.hasPrefix("repo:") }).dropFirst(5)
            #expect(["acme/app", "partner/private"].contains(String(repository)))
            requestedRepositories.insert(String(repository))
            if qualifiers.contains("is:open") {
                requestedStates.insert("open")
                return self.page([self.node(1, repository: String(repository))])
            }
            #expect(qualifiers.contains("is:merged"))
            let cutoff = ISO8601DateFormatter().string(from: self.now.addingTimeInterval(-86_400))
            #expect(qualifiers.contains("merged:>=\(cutoff)"))
            requestedStates.insert("merged")
            return self.page([])
        }
        let prs = try GitHubClient(executable: gh, runner: runner)
            .load(repositories: ["partner/private", "acme/app", "acme/app"], now: now)
        #expect(requestedRepositories == ["acme/app", "partner/private"])
        #expect(requestedStates == ["open", "merged"])
        #expect(Set(prs.map(\.repository)) == requestedRepositories)
        #expect(prs.count == 2)
    }

    @Test func testPaginatesOpenAndMergedAndIncludesDraftsAtExactCutoff() throws {
        let cutoff = now.addingTimeInterval(-86_400)
        let runner = StubRunner(responses: [
            viewer(),
            page([node(1, draft: true, updated: cutoff.addingTimeInterval(-100), review: "REVIEW_REQUIRED", checks: "PENDING")], next: "open-next"),
            page([node(2, review: "APPROVED", checks: "SUCCESS")]),
            page([node(3, state: "MERGED", merged: now.addingTimeInterval(-60)),
                  node(4, state: "MERGED", merged: cutoff.addingTimeInterval(-1), updated: now)], next: "merged-next"),
            page([node(5, state: "MERGED", merged: cutoff, updated: cutoff)])
        ])
        let prs = try load(runner)
        #expect(Set(prs.map(\.number)) == [1, 2, 3, 5])
        let draft = try #require(prs.first { $0.number == 1 })
        #expect(draft.isDraft)
        #expect(draft.reviewDecision == "REVIEW_REQUIRED")
        #expect(draft.checks == "PENDING")
        #expect(prs.first { $0.number == 2 }?.checks == "SUCCESS")
    }

    @Test func testRecentlyUpdatedOldMergeDoesNotHideLaterRecentMerge() throws {
        let runner = StubRunner(responses: [
            viewer(), page([]),
            page([node(1, state: "MERGED", merged: now.addingTimeInterval(-200_000), updated: now)], next: "next"),
            page([node(2, state: "MERGED", merged: now.addingTimeInterval(-100), updated: now.addingTimeInterval(-100))])
        ])
        let prs = try load(runner)
        #expect(prs.map(\.number) == [2])
    }

    @Test func testReviewAndCheckStatesAndAbsentChecksMapWithoutGuessing() throws {
        let states = ["SUCCESS", "FAILURE", "PENDING", "ERROR", "EXPECTED"]
        var nodes = states.enumerated().map { index, state in
            node(index + 1, review: "CHANGES_REQUESTED", checks: state)
        }
        var noCommit = node(7)
        noCommit["commits"] = ["nodes": []]
        nodes += [node(6), noCommit]
        let runner = StubRunner(responses: [viewer(), page(nodes), page([])])
        let prs = try load(runner)
        for (index, state) in states.enumerated() {
            #expect(prs.first { $0.number == index + 1 }?.checks == state)
            #expect(prs.first { $0.number == index + 1 }?.reviewDecision == "CHANGES_REQUESTED")
        }
        #expect(prs.first { $0.number == 6 }?.checks == nil)
        #expect(prs.first { $0.number == 7 }?.checks == nil)
    }

    @Test func testNullForkAndFractionalTimestampsDecode() throws {
        var pr = node(1)
        pr["headRepository"] = NSNull()
        pr["updatedAt"] = "2027-01-15T08:00:00.123Z"
        let runner = StubRunner(responses: [viewer(), page([pr]), page([])])
        let prs = try load(runner)
        #expect(prs.count == 1)
        #expect(prs[0].headRepository == nil)
        #expect(prs[0].repository == "acme/app")
        #expect(prs[0].headBranch == "feature-1")
    }

    @Test func testRepeatedPaginationCursorFailsInsteadOfLooping() {
        let runner = StubRunner(responses: [viewer(), page([node(1)], next: "same"), page([node(2)], next: "same")])
        expectFailure(containing: "pagination cursor") { _ = try load(runner) }
    }

    @Test func testMissingPaginationCursorFailsInsteadOfReturningPartialResults() {
        let response = json(["data": ["search": [
            "issueCount": 2, "nodes": [node(1)],
            "pageInfo": ["hasNextPage": true, "endCursor": NSNull()]
        ]]])
        let runner = StubRunner(responses: [viewer(), response])
        expectFailure(containing: "pagination cursor") { _ = try load(runner) }
    }

    @Test func testSearchLimitFailsExplicitlyInsteadOfSilentlyTruncating() {
        let runner = StubRunner(responses: [viewer(), page([node(1)], next: "next", total: 1_001)])
        expectFailure(containing: "1,000") { _ = try load(runner) }
    }

    @Test func testExactlyOneThousandResultsCanComplete() throws {
        let nodes = (1...1_000).map { node($0) }
        var responses = [viewer()]
        for start in stride(from: 0, to: nodes.count, by: 100) {
            let end = start + 100
            responses.append(page(Array(nodes[start..<end]), next: end < nodes.count ? "page-\(end)" : nil, total: 1_000))
        }
        responses.append(page([]))
        let prs = try load(StubRunner(responses: responses))
        #expect(prs.count == 1_000)
    }

    @Test func testChangingSearchCountCannotSilentlyCrossLimit() {
        let nodes = (1...100).map { node($0) }
        var responses = [viewer()]
        for pageNumber in 1...10 {
            responses.append(page(nodes, next: "page-\(pageNumber)", total: 1_000))
        }
        expectFailure(containing: "1,000") { _ = try load(StubRunner(responses: responses)) }
    }

    @Test func testAuthFailurePreservesActionableCLIError() {
        let failure = CommandResult(status: 1, output: Data(), error: Data("authentication required".utf8))
        let runner = StubRunner(responses: [failure])
        expectFailure(containing: "authentication required") { _ = try load(runner) }
        expectFailure(containing: "gh auth login") {
            _ = try GitHubClient(executable: gh, runner: StubRunner(responses: [failure])).repositories()
        }
    }

    @Test func testGraphQLErrorsDoNotReturnAnApparentlySuccessfulEmptyList() {
        let failure = json(["data": NSNull(), "errors": [["message": "API rate limit exceeded"]]])
        expectFailure(containing: "API rate limit exceeded") {
            _ = try load(StubRunner(responses: [viewer(), failure]))
        }
    }

    @Test func testFailureInLaterRepositoryDoesNotClaimPartialSuccess() {
        let failure = json(["errors": [["message": "Resource not accessible by integration"]]])
        let runner = StubRunner(responses: [viewer(), page([node(1)]), page([]), failure])
        expectFailure(containing: "Resource not accessible") {
            _ = try GitHubClient(executable: gh, runner: runner).load(repositories: ["acme/app", "partner/private"], now: now)
        }
    }

    @Test func testDuplicatePaginationNodesAppearOnlyOnce() throws {
        let runner = StubRunner(responses: [viewer(), page([node(1)], next: "next"), page([node(1), node(2)]), page([])])
        let prs = try load(runner)
        #expect(prs.count == 2)
    }

    @Test func testCatalogPaginatesAndPreservesPrivateOrganizationAndCollaboratorRepositories() throws {
        let runner = StubRunner()
        runner.handler = { arguments in
            switch self.variables(arguments)["cursor"] {
            case nil:
                return self.catalog([self.repository("me/owned")], next: "organization-page")
            case "organization-page":
                return self.catalog([self.repository("organization/private", isPrivate: true)], next: "collaborator-page")
            case "collaborator-page":
                return self.catalog([self.repository("partner/collaboration"), self.repository("me/owned")])
            default:
                throw BackendError.message("Unknown catalog page")
            }
        }
        let repositories = try GitHubClient(executable: gh, runner: runner).repositories()
        #expect(repositories.map(\.nameWithOwner) == ["me/owned", "organization/private", "partner/collaboration"])
        #expect(repositories.first { $0.nameWithOwner == "organization/private" }?.isPrivate == true)
    }

    @Test func testCatalogHasNoSearchResultCap() throws {
        var responses: [CommandResult] = []
        for index in 0..<11 {
            let nodes = (0..<100).map { repository("org/repo-\(index * 100 + $0)") }
            responses.append(catalog(nodes, next: index < 10 ? "page-\(index)" : nil))
        }
        let repositories = try GitHubClient(executable: gh, runner: StubRunner(responses: responses)).repositories()
        #expect(repositories.count == 1_100)
    }

    @Test func testCatalogRepeatedCursorAndGraphQLErrorsFail() {
        let runner = StubRunner(responses: [catalog([], next: "same"), catalog([], next: "same")])
        expectFailure(containing: "pagination cursor") {
            _ = try GitHubClient(executable: gh, runner: runner).repositories()
        }
        let failure = json(["data": ["viewer": ["repositories": NSNull()]], "errors": [["message": "Bad credentials"]]])
        expectFailure(containing: "Bad credentials") {
            _ = try GitHubClient(executable: gh, runner: StubRunner(responses: [failure])).repositories()
        }
    }

    private var gh: URL { URL(fileURLWithPath: "/test/gh") }

    private func load(_ runner: StubRunner) throws -> [PullRequest] {
        try GitHubClient(executable: gh, runner: runner).load(repositories: ["acme/app"], now: now)
    }

    private func expectFailure(containing text: String, _ operation: () throws -> Void) {
        do {
            try operation()
            Issue.record("Expected failure containing \(text)")
        } catch {
            #expect(error.localizedDescription.contains(text))
        }
    }

    // Interpret GraphQL variable values, rather than asserting an exact CLI invocation.
    private func variables(_ arguments: [String]) -> [String: String] {
        var values: [String: String] = [:]
        for argument in arguments {
            guard let separator = argument.firstIndex(of: "=") else { continue }
            values[String(argument[..<separator])] = String(argument[argument.index(after: separator)...])
        }
        return values
    }

    private func node(_ number: Int, repository: String = "acme/app", state: String = "OPEN", draft: Bool = false,
                      merged: Date? = nil, updated: Date? = nil, review: String? = nil,
                      checks: String? = nil) -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        var node: [String: Any] = [
            "number": number, "title": "Change \(number)", "url": "https://github.com/\(repository)/pull/\(number)",
            "state": state, "isDraft": draft, "mergedAt": merged.map { formatter.string(from: $0) } as Any? ?? NSNull(),
            "updatedAt": formatter.string(from: updated ?? now), "headRefName": "feature-\(number)", "baseRefName": "main",
            "repository": ["nameWithOwner": repository], "headRepository": ["nameWithOwner": repository],
            "labels": ["nodes": []],
            "reviewDecision": review as Any? ?? NSNull()
        ]
        let rollup: Any = checks.map { ["state": $0] } as Any? ?? NSNull()
        node["commits"] = ["nodes": [["commit": ["statusCheckRollup": rollup]]]]
        return node
    }

    private func viewer(login: String = "me") -> CommandResult {
        json(["data": ["viewer": ["login": login]]])
    }

    private func page(_ nodes: [[String: Any]], next: String? = nil, total: Int? = nil) -> CommandResult {
        json(["data": ["search": [
            "issueCount": total ?? nodes.count, "nodes": nodes,
            "pageInfo": ["hasNextPage": next != nil, "endCursor": next as Any? ?? NSNull()]
        ]]])
    }

    private func repository(_ name: String, isPrivate: Bool = false) -> [String: Any] {
        ["nameWithOwner": name, "isPrivate": isPrivate]
    }

    private func catalog(_ nodes: [[String: Any]], next: String? = nil) -> CommandResult {
        json(["data": ["viewer": ["repositories": [
            "nodes": nodes,
            "pageInfo": ["hasNextPage": next != nil, "endCursor": next as Any? ?? NSNull()]
        ]]]])
    }

    private func json(_ object: [String: Any]) -> CommandResult {
        CommandResult(status: 0, output: try! JSONSerialization.data(withJSONObject: object), error: Data())
    }
}

final class StubRunner: CommandRunning {
    var responses: [CommandResult]
    var calls: [[String]] = []
    var handler: (([String]) throws -> CommandResult)?

    init(responses: [CommandResult] = []) { self.responses = responses }

    func run(executable: URL, arguments: [String], timeout: TimeInterval) throws -> CommandResult {
        calls.append(arguments)
        if let handler { return try handler(arguments) }
        guard !responses.isEmpty else { throw BackendError.message("Unexpected command in test: \(arguments)") }
        return responses.removeFirst()
    }
}
