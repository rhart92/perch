# Perch

A native macOS menu bar app for your GitHub pull requests. Requires macOS 14 or later and an authenticated [GitHub CLI](https://cli.github.com/).

The menu panel uses the dark Rosé Pine **Moon** palette, including in macOS light mode. It starts directly with the **Open → Drafts → Merged → All** tabs, each displaying its PR count, with no separate count row or branding header. Counts reflect all loaded PRs rather than only the selected tab; Merged includes only the last 24 hours. **Open** is selected on launch. Refresh lives in the footer and remains available through **⌘R**.

Tabs use icon labels and a soft rounded selection pill that slides between tabs with a spring animation. macOS **Reduce Motion** disables the sliding animation; PR-list updates are not animated with the tab pill.

The panel is 440 points wide and up to 1,000 points tall, capped to the available screen height with 32 points of clearance. Long PR lists remain scrollable; PR text and decorative card surfaces do not capture mouse-wheel input. Both the PR list and repository picker use overlay scrollbars that appear while scrolling and fade out when idle, without reserving a permanent scrollbar gutter.

The menu is a native popover anchored to the menu-bar icon, not a separate floating panel. It opens and closes immediately, without a presentation animation, so its controls stay aligned with mouse input. Click the icon again or press **Escape** to dismiss it. Outside clicks dismiss it when no text field is being edited. While editing, it stays open across external focus changes so a picker does not dismiss the input destination; use Escape or the icon to close it when finished.

Text fields support the standard macOS editing commands: undo/redo, cut, copy, paste, and select all. **⌘Q** quits the app.

## Build and run

Install Apple's command line tools if needed (`xcode-select --install`), then:

```sh
brew install gh
gh auth login
./build.sh
open dist/Perch.app
```

Click the layers icon in the menu bar. Perch has no Dock icon and opens no standalone window on launch or reopen; repository settings live inside the popover. The build script creates a release `.app` bundle and signs it locally with an ad-hoc signature; it is not notarized. You can copy `dist/Perch.app` to `/Applications`. No Xcode project or third-party Swift packages are required.

For development:

```sh
swift run Perch
./test.sh
```

The test script uses Swift Testing and handles its framework search path on command-line-tools-only installations.

## Pull requests

- PRs authored by the account currently authenticated in `gh`, **only in repositories you select**: ready-for-review **Open**, **Draft**, and **Merged** in the rolling last 24 hours. Closed-but-unmerged PRs are excluded.
- Repository and PR results are paginated. PR searches are scoped by repository and author on GitHub, not loaded account-wide and filtered afterward.
- Open/Drafts/Merged/All filters, review decisions, and aggregate checks for the latest commit. An absent review/check result is shown as unavailable, not assumed to be passing.
- Automatically refreshes on launch, every minute, and after wake. Refresh manually with the arrow or **⌘R** while the panel is open. If refresh fails, the panel reports the error and retains the last successful results for this session.
- PR numbers are literal identifiers without thousands separators, such as `#373698`. The repo/number and title are not link targets; click the compact **GitHub icon** beside the other actions to open the PR. Right-click that icon to open its context menu for opening the PR or copying its URL.
- Open and draft cards have compact **GitHub**, **merge**, and **close** icon buttons. Merged cards show only the **GitHub** button; merge and close controls are omitted in every tab. The merge glyph adds the literal `merge` queue label; it does **not** merge the PR directly or apply a completed-merge label. The label must already exist in the repository, and repository automation may react to it.
- The merge-queue action is disabled for drafts: mark the PR ready for review on GitHub first. Draft status is never changed automatically. The action reads the label back from GitHub before reporting success, and the icon reflects fetched label state rather than a sticky local flag. A follow-up refresh after eight seconds catches labels removed by queue automation; regular refreshes continue afterward. Label presence does not guarantee that the queue will merge the PR.
- Close expands an inline confirmation inside the PR card, keeping the menu-bar panel open. **Cancel** dismisses confirmation; **Close PR** closes without merging and leaves the branch intact. Successfully closed PRs disappear from the list. Both actions use your existing `gh` login and require repository write permissions; progress and failures appear on the card.
- When a PR has open descendants, confirmation offers an unchecked **Also close N PRs above this one** option. It includes open/draft descendants from the full loaded stack, even if hidden by the current filter, but excludes merged PRs, ancestors, and sibling branches. The confirmation lists the additional PR numbers and updates the close-button count.
- Stack closes run descendants-first and close the selected PR last. A failure stops the operation, reports how many PRs closed and where it stopped, and leaves remaining PRs open. Completed closes are not rolled back. Without the option selected, only the selected PR closes.

Perch reads metadata through authenticated `gh api graphql` and performs the two explicit quick actions through `gh pr edit --add-label merge` and `gh pr close`; it does not store a GitHub token. It does not scan local folders, run Git commands, or require checkouts. No LLM service is used.

GitHub search has a 1,000-result limit per repository and state query. If your authored open PRs or last-24-hour merges exceed that limit, Perch reports an explicit error rather than silently displaying an incomplete list. GitHub's search index can lag new PRs and status changes.

## PR stacks

PRs are grouped when a child's base branch matches another PR's head branch in the same repository. The view lists the base PR first and indents descendants. Fork repository identities are respected; ambiguous branch matches are not guessed. Standalone PRs remain visible.

Stacks and standalone PRs are sorted **most recently updated first**, across repositories. A stack uses the latest GitHub update timestamp among all its loaded members, including members hidden by the current tab. Equal timestamps fall back to repository name and base PR number for deterministic ordering. Within each stack, dependency order remains base-first and depth-first, with sibling branches ordered by PR number.

Single-PR groups render as just the PR card, without a stack heading, icon, or count row. Multi-PR stacks retain a heading with a stacked-cards icon, even if the current filter shows only one member. Groups initially use **Stack #<base PR number>**. **Double-click a group name** to replace the title with a single inline input, with no separate window, Save/Cancel buttons, or helper text. **Enter** saves; **Escape** cancels the edit without closing the popover. Save an empty name to restore the automatic name. Names are local metadata, keyed by repository and base PR number, and persist across launches. Branch names are used internally for grouping but are not displayed on PR cards.

Click the **copy icon beside a stack name** to share it. The first line is **PR Stack for &lt;stack name&gt;**, using the configured name (or automatic name), followed by a blank line and each PR title linked to its GitHub URL in base-first stack order. Copy includes the full loaded stack, even when the current tab hides members. The clipboard includes HTML and RTF for rich-text pasting into Slack, Notion, and other editors; the plain-text fallback includes each title and URL.

A successful stack copy shows a non-blocking **Copied stack** toast inside the popover for two seconds. Copying again restarts the timer; closing the popover clears the message. The toast does not take focus or intercept mouse input, and a matching accessibility announcement confirms the copy for screen-reader users.

This is branch-based grouping, not commit ancestry inference. Only your loaded PRs participate: another author's PR, a closed PR, or a merge older than 24 hours is not included as an ancestor. GitHub retargeting branches can change the inferred grouping and its base identity.

## Choose repositories

The repository picker opens on first launch. Open it again with the **gear button**:

1. The list comes from repositories accessible to your authenticated GitHub account/token: owned repositories, collaborator repositories, and organization repositories, including private repositories that the token can access.
2. Search the list locally and check the repositories you want to track. Selections save immediately and trigger a scoped PR refresh.
3. Click **Done** to return to your PRs.

**Nothing is selected by default. With no repositories selected, Perch makes no PR requests.** Deselecting a repository immediately removes its PRs and cancels an in-progress load for the old selection. There is no fallback to querying all repositories.

The repository catalog is fetched when configuration first opens and cached for the session; it is not reloaded every minute. **Reload** fetches it again, useful after token/account or access changes. Selected repositories missing from the current catalog remain listed so they can be deselected. Repository selection does not change GitHub token permissions.

Selections and stack names are saved in macOS user defaults under `com.rhart.perch` when running the packaged app. Old local-folder preferences are removed on launch. PR data and the repository catalog are held in memory, not cached to disk.

Use **Quit** or **⌘Q** in the panel to exit. Perch does not configure launch at login.
