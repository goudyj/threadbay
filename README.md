# ThreadBay

ThreadBay is a macOS app for working on multiple Git branches in parallel and running development agents in integrated terminals.

## How It Works

1. Add a project from the settings by selecting its local Git repository.
2. Create a **space** from a new branch, an existing branch, or a GitHub pull request.
3. ThreadBay creates an independent clone next to the source repository, then checks out the selected branch. Each task has its own directory and does not affect other spaces.
4. From that space, launch Claude Code, Codex, a shell, or a custom command in the integrated terminal. Multiple sessions can run at the same time.
5. Open the directory in VS Code, Zed, Cursor, or Finder. Deleting a space stops its sessions, removes its directory, and removes it from ThreadBay.

The app remains accessible from the menu bar and can send a notification when an agent finishes a turn or waits for an action. Projects, spaces, and agents are stored in local YAML files:

- `~/Library/Application Support/com.jlex.threadbay/settings.yaml`
- `~/.threadbay/spaces.yaml`
- `~/Library/Application Support/com.jlex.threadbay/agents.yaml`

## Requirements

- macOS 14 or later;
- Swift 6, provided by Xcode or the Command Line Tools;
- Git;
- `gh` to create a space from a pull request;
- the commands for the agents or editors you want to use (`claude`, `codex`, `code`, `zed`, `cursor`, etc.).

## Build from Source

```bash
git clone https://github.com/goudyj/threadbay.git
cd threadbay
swift build
swift test
./scripts/run-app.sh
```

Swift Package Manager downloads dependencies automatically during the first build. The launcher builds in debug mode, then opens the macOS app bundle, which is required to test notifications. To create a release build without launching it:

```bash
./scripts/build-app.sh
```

The script compiles in release mode, assembles `ThreadBay.app` at the project root, and signs it locally. You can then move it to the `Applications` folder.
