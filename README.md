# Perch

Keep an eye on your GitHub pull requests from your Mac’s menu bar. See what is ready, what needs work, and what was merged—all in one place.

## What it does

- Shows your open pull requests, drafts, and merges from the last 24 hours.
- Lets you choose which GitHub repos to watch. A repo is a project stored on GitHub.
- Shows review status and whether checks passed.
- Groups pull requests that build on each other into stacks.
- Lets you name a stack and copy its links to share with your team.
- Opens pull requests on GitHub and lets you close them from the app.
- Refreshes every minute, or when you ask it to.

Perch can also add a `merge` label to a pull request. If your repo uses that label to start a merge queue, this can send it to the queue. Perch does not merge code itself.

## Get started

You need macOS 14 or later, Apple’s command line tools, and the [GitHub CLI](https://cli.github.com/).

If you need Apple’s command line tools, run:

```sh
xcode-select --install
```

With [Homebrew](https://brew.sh/) installed, run these commands from the Perch folder:

```sh
brew install gh
gh auth login
./build.sh
open dist/Perch.app
```

Click the layers icon in your menu bar. Choose the repos you want to watch, then click **Done**. Perch only shows pull requests you wrote in those repos.

You can copy `dist/Perch.app` to your Applications folder. Perch stays in the menu bar, not the Dock.

## Your account

Perch uses your GitHub CLI sign-in. It does not store a separate GitHub token or need a local copy of your repos. Your repo choices and stack names stay on your Mac.
