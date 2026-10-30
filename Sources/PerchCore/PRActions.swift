import Foundation

public enum PRAction: Sendable, Equatable {
    case addMergeLabel
    case close
}

public enum PRActions {
    public static func perform(_ action: PRAction, on pr: PullRequest) async throws {
        let work = Task.detached(priority: .userInitiated) {
            let executable = try GitHubClient.findExecutable()
            try PRActionClient(executable: executable, runner: ProcessRunner()).perform(action, on: pr)
        }
        try await withTaskCancellationHandler(operation: {
            try await work.value
        }, onCancel: {
            work.cancel()
        })
    }
}

struct PRActionClient {
    let executable: URL
    let runner: CommandRunning

    func perform(_ action: PRAction, on pr: PullRequest) throws {
        guard pr.state == "OPEN" else {
            throw BackendError.message("Only open pull requests can be labeled for merge or closed.")
        }
        if action == .addMergeLabel && pr.isDraft {
            throw BackendError.message("Draft PRs cannot enter the merge queue. Mark this PR ready for review on GitHub first.")
        }
        let arguments: [String]
        let description: String
        switch action {
        case .addMergeLabel:
            arguments = ["pr", "edit", pr.url.absoluteString, "--add-label", "merge"]
            description = "add the merge label"
        case .close:
            arguments = ["pr", "close", pr.url.absoluteString]
            description = "close the pull request"
        }
        let result = try runner.run(executable: executable, arguments: arguments, timeout: 60)
        guard result.status == 0 else {
            let detail = result.errorText.isEmpty
                ? "GitHub CLI exited with status \(result.status)."
                : result.errorText
            throw BackendError.message("Could not \(description) for \(pr.repository)#\(pr.number). \(detail)")
        }
        if action == .addMergeLabel {
            let confirmation = try runner.run(
                executable: executable,
                arguments: ["pr", "view", pr.url.absoluteString, "--json", "labels"],
                timeout: 60
            )
            guard confirmation.status == 0 else {
                throw BackendError.message("The label request completed, but GitHub confirmation failed. \(confirmation.errorText) Refresh before trying again.")
            }
            let labels: LabelConfirmation
            do {
                labels = try JSONDecoder().decode(LabelConfirmation.self, from: confirmation.output)
            } catch {
                throw BackendError.message("The label request completed, but GitHub returned an unreadable label confirmation. Refresh before trying again.")
            }
            guard labels.labels.contains(where: { $0.name.caseInsensitiveCompare("merge") == .orderedSame }) else {
                throw BackendError.message("GitHub did not retain the merge label. Repository automation may have removed it; check the PR's timeline.")
            }
        }
    }

    private struct LabelConfirmation: Decodable {
        let labels: [Label]
        struct Label: Decodable { let name: String }
    }
}
