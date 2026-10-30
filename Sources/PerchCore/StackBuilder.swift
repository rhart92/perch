import Foundation

public enum StackBuilder {
    public static func group(_ prs: [PullRequest]) -> [PRStack] {
        var unique: [String: PullRequest] = [:]
        for pr in prs where unique[pr.id] == nil { unique[pr.id] = pr }
        let ordered = unique.values.sorted(by: precedes)
        var heads: [BranchIdentity: [String]] = [:]
        for pr in ordered {
            // A missing head repository can mean a deleted fork, not the target repository.
            guard let headRepository = pr.headRepository else { continue }
            let key = BranchIdentity(repository: headRepository, branch: pr.headBranch)
            heads[key, default: []].append(pr.id)
        }

        var parents: [String: String] = [:]
        for child in ordered {
            let base = BranchIdentity(repository: child.repository, branch: child.baseBranch)
            let candidates = (heads[base] ?? []).filter { id in
                id != child.id && unique[id]!.repository.lowercased() == child.repository.lowercased()
            }
            // Reused branch names are ambiguous; never invent an ancestry relationship.
            if candidates.count == 1 { parents[child.id] = candidates[0] }
        }

        // Each node has at most one parent. Break each cycle at its smallest PR so
        // API ordering never changes the root, and every PR remains visible.
        var resolved = Set<String>()
        for pr in ordered where !resolved.contains(pr.id) {
            var path: [String] = []
            var positions: [String: Int] = [:]
            var current: String? = pr.id
            while let id = current, !resolved.contains(id) {
                if let start = positions[id] {
                    let root = path[start...].min { precedes(unique[$0]!, unique[$1]!) }!
                    parents.removeValue(forKey: root)
                    break
                }
                positions[id] = path.count
                path.append(id)
                current = parents[id]
            }
            resolved.formUnion(path)
        }

        var children: [String: [PullRequest]] = [:]
        for pr in ordered {
            if let parent = parents[pr.id] { children[parent, default: []].append(pr) }
        }
        var stacks = ordered.filter { parents[$0.id] == nil }.map { root in
            var members: [PullRequest] = []
            var depths: [String: Int] = [:]
            var pending: [(PullRequest, Int)] = [(root, 0)]
            while let (pr, depth) = pending.popLast() {
                members.append(pr)
                depths[pr.id] = depth
                for child in (children[pr.id] ?? []).reversed() {
                    pending.append((child, depth + 1))
                }
            }
            return PRStack(
                id: "\(root.repository)#\(root.number)",
                name: members.count > 1 ? "Stack #\(root.number)" : "\(root.repository) #\(root.number)",
                pullRequests: members,
                depths: depths
            )
        }
        stacks.sort {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return precedes($0.pullRequests[0], $1.pullRequests[0])
        }
        return stacks
    }

    private struct BranchIdentity: Hashable {
        let repository: String
        let branch: String

        init(repository: String, branch: String) {
            self.repository = repository.lowercased()
            self.branch = branch
        }
    }

    private static func precedes(_ lhs: PullRequest, _ rhs: PullRequest) -> Bool {
        let leftRepository = lhs.repository.lowercased()
        let rightRepository = rhs.repository.lowercased()
        if leftRepository != rightRepository { return leftRepository < rightRepository }
        if lhs.number != rhs.number { return lhs.number < rhs.number }
        return lhs.id < rhs.id
    }
}
