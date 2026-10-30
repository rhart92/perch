import Foundation
import Testing
@testable import PerchCore

struct StackBuilderTests {
    @Test func testBranchedStackIsBaseFirstDepthFirstAndOrderIndependent() {
        let root = makePR(10, head: "foundation")
        let left = makePR(20, head: "left", base: "foundation")
        let right = makePR(30, head: "right", base: "foundation")
        let leaf = makePR(40, head: "leaf", base: "left")
        let input = [right, leaf, left, root]
        let stack = StackBuilder.group(input)
        #expect(stack.count == 1)
        #expect(stack[0].pullRequests.map(\.number) == [10, 20, 40, 30])
        #expect(stack[0].depths == [root.id: 0, left.id: 1, leaf.id: 2, right.id: 1])
        #expect(StackBuilder.group(Array(input.reversed()))[0].pullRequests.map(\.id) == stack[0].pullRequests.map(\.id))
    }

    @Test func testRepositoryAndBranchCaseBoundaries() {
        let root = makePR(1, head: "Feature")
        let otherRepository = makePR(2, repository: "acme/other", head: "child", base: "Feature")
        let caseMismatch = makePR(3, head: "child", base: "feature")
        #expect(StackBuilder.group([root, otherRepository, caseMismatch]).count == 3)
        let sameRepository = makePR(4, repository: "ACME/APP", head: "nested", base: "Feature")
        #expect(StackBuilder.group([sameRepository, root]).count == 1)
    }

    @Test func testForkHeadCannotParentTargetRepositoryBranch() {
        let fork = makePR(1, headRepository: "contributor/app", head: "feature")
        let child = makePR(2, head: "child", base: "feature")
        #expect(StackBuilder.group([fork, child]).count == 2)
        let deletedFork = makePR(3, headRepository: nil, head: "feature")
        #expect(StackBuilder.group([deletedFork, child]).count == 2)
    }

    @Test func testDoesNotJoinAcrossTargetRepositoriesEvenIfForkIdentityMatches() {
        let upstreamPR = makePR(1, repository: "upstream/app", headRepository: "acme/app", head: "feature")
        let forkPR = makePR(2, head: "child", base: "feature")
        #expect(StackBuilder.group([upstreamPR, forkPR]).count == 2)
    }

    @Test func testCycleBreaksAtSmallestPRWithoutLosingDescendants() {
        let a = makePR(1, head: "a", base: "c")
        let b = makePR(2, head: "b", base: "a")
        let c = makePR(3, head: "c", base: "b")
        let branch = makePR(4, head: "branch", base: "b")
        for input in [[c, a, branch, b], [branch, b, a, c]] {
            let groups = StackBuilder.group(input)
            #expect(groups.count == 1)
            #expect(groups[0].pullRequests.map(\.number) == [1, 2, 3, 4])
            #expect(groups[0].depths[branch.id] == 2)
        }
    }

    @Test func testSelfReferenceAndAmbiguousHeadsStayVisibleWithoutInventedParents() {
        let a = makePR(1, head: "shared", base: "shared")
        #expect(StackBuilder.group([a])[0].depths[a.id] == 0)
        let b = makePR(2, head: "shared")
        let child = makePR(3, head: "child", base: "shared")
        let groups = StackBuilder.group([a, b, child, child])
        #expect(groups.flatMap(\.pullRequests).count == 3)
        let childGroup = groups.first { $0.pullRequests.contains { $0.id == child.id } }!
        #expect(childGroup.depths[child.id] == 0)
    }

    @Test func testLongStackUsesActualBranchDepth() {
        let prs = (1...500).map { number in
            makePR(number, head: "branch-\(number)", base: number == 1 ? "main" : "branch-\(number - 1)")
        }
        let groups = StackBuilder.group(Array(prs.reversed()))
        #expect(groups.count == 1)
        #expect(groups[0].pullRequests.count == 500)
        #expect(groups[0].depths[prs.last!.id] == 499)
        #expect(StackBuilder.group([]).isEmpty)
    }

    @Test func testCloseDescendantsRespectSubtreesAndPutParentsLast() {
        let root = makePR(10, head: "root")
        let left = makePR(20, head: "left", base: "root")
        let right = makePR(30, head: "right", base: "root")
        let leaf = makePR(40, head: "leaf", base: "left")
        let stack = StackBuilder.group([leaf, right, root, left])[0]
        let all = stack.openDescendants(above: root.id)
        #expect(Set(all.map(\.number)) == [20, 30, 40])
        #expect(all.firstIndex(where: { $0.id == leaf.id })! < all.firstIndex(where: { $0.id == left.id })!)
        #expect(stack.openDescendants(above: left.id).map(\.number) == [40])
        #expect(stack.openDescendants(above: right.id).isEmpty)
        #expect(stack.openDescendants(above: leaf.id).isEmpty)
        #expect(stack.openDescendants(above: "missing").isEmpty)
    }

    @Test func testCloseDescendantsSkipMergedPRsButIncludeDraftsAboveThem() {
        let root = makePR(10, head: "root")
        let merged = PullRequest(number: 20, title: "Merged", url: URL(string: "https://github.com/acme/app/pull/20")!,
                                repository: "acme/app", headRepository: "acme/app", headBranch: "merged",
                                baseBranch: "root", isDraft: false, state: "MERGED", mergedAt: Date(),
                                updatedAt: Date(), reviewDecision: nil, checks: nil)
        let draft = PullRequest(number: 30, title: "Draft", url: URL(string: "https://github.com/acme/app/pull/30")!,
                               repository: "acme/app", headRepository: "acme/app", headBranch: "draft",
                               baseBranch: "merged", isDraft: true, state: "OPEN", mergedAt: nil,
                               updatedAt: Date(), reviewDecision: nil, checks: nil)
        let stack = StackBuilder.group([draft, merged, root])[0]
        #expect(stack.openDescendants(above: root.id).map(\.number) == [30])
    }

    @Test func testGroupsSortByLatestUpdateAcrossRepositoriesAndPRNumbers() {
        let oldest = makePR(300, repository: "aaa/app", updated: 10)
        let newest = makePR(1, repository: "zzz/app", updated: 30)
        let middle = makePR(200, repository: "aaa/app", updated: 20)
        let groups = StackBuilder.group([oldest, newest, middle])
        #expect(groups.map { $0.pullRequests[0].number } == [1, 200, 300])
    }

    @Test func testUpdatedDescendantPromotesStackWithoutReorderingDependencies() {
        let base = makePR(10, head: "base", updated: 10)
        let child = makePR(20, head: "child", base: "base", updated: 50)
        let sibling = makePR(30, head: "sibling", base: "base", updated: 40)
        let standalone = makePR(40, updated: 30)
        let groups = StackBuilder.group([standalone, sibling, child, base])
        #expect(groups.map { $0.pullRequests[0].number } == [10, 40])
        #expect(groups[0].pullRequests.map(\.number) == [10, 20, 30])
        let olderChild = makePR(20, head: "child", base: "base", updated: 20)
        let olderSibling = makePR(30, head: "sibling", base: "base", updated: 20)
        let refreshed = StackBuilder.group([base, standalone, olderChild, olderSibling])
        #expect(refreshed.map { $0.pullRequests[0].number } == [40, 10])
    }

    @Test func testEqualUpdateTimesKeepDeterministicRepositoryAndBaseNumberOrder() {
        let input = [makePR(30, repository: "zzz/app"), makePR(20), makePR(10)]
        let forward = StackBuilder.group(input).map(\.id)
        #expect(forward == ["acme/app#10", "acme/app#20", "zzz/app#30"])
        #expect(StackBuilder.group(Array(input.reversed())).map(\.id) == forward)
    }
}

func makePR(_ number: Int, repository: String = "acme/app", headRepository: String? = "acme/app",
            head: String = "feature", base: String = "main", updated: TimeInterval = 1_700_000_000) -> PullRequest {
    PullRequest(number: number, title: "Change \(number)",
                url: URL(string: "https://github.com/\(repository)/pull/\(number)")!,
                repository: repository, headRepository: headRepository, headBranch: head, baseBranch: base,
                isDraft: false, state: "OPEN", mergedAt: nil, updatedAt: Date(timeIntervalSince1970: updated),
                reviewDecision: nil, checks: nil)
}
