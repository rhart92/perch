import Foundation
import Testing
@testable import PerchCore

struct PRActionsTests {
    @Test func draftQueueRequestFailsBeforeAnyMutation() {
        let runner = StubRunner()
        let client = PRActionClient(executable: URL(fileURLWithPath: "/fixture/gh"), runner: runner)
        do {
            try client.perform(.addMergeLabel, on: pr(draft: true))
            Issue.record("Draft PRs must not be queued")
        } catch {
            #expect(error.localizedDescription.contains("ready for review"))
        }
        #expect(runner.calls.isEmpty)
    }

    @Test func successfulCommandWithoutRetainedLabelDoesNotReportSuccess() {
        let runner = StubRunner(responses: [
            CommandResult(status: 0, output: Data(), error: Data()),
            CommandResult(status: 0, output: Data("{\"labels\":[]}".utf8), error: Data()),
        ])
        do {
            try PRActionClient(executable: URL(fileURLWithPath: "/fixture/gh"), runner: runner)
                .perform(.addMergeLabel, on: pr())
            Issue.record("A removed label must not be reported as applied")
        } catch {
            #expect(error.localizedDescription.contains("did not retain"))
        }
    }

    private func pr(draft: Bool = false) -> PullRequest {
        PullRequest(number: 1, title: "Queue regression", url: URL(string: "https://github.com/example/fixture/pull/1")!,
                    repository: "example/fixture", headRepository: "example/fixture", headBranch: "feature",
                    baseBranch: "main", isDraft: draft, state: "OPEN", mergedAt: nil,
                    updatedAt: Date(timeIntervalSince1970: 1_800_000_000), reviewDecision: nil, checks: nil)
    }
}
