# VaultSync

VaultSync is a macOS menu bar app for pushing a local vault folder to a Git remote repository.

It is designed for folders that live in iCloud Drive or other synced directories, while the hidden base repository is managed separately by the app and linked through a real `git worktree`.

## Features

- Menu bar app with a compact status popover
- Separate setup window for onboarding and editing
- Real `git worktree`-based vault management
- One-way sync model: local vault changes are committed and pushed to the remote repository
- Change detection via macOS file system events instead of constant polling
- Optional force-push mode with an explicit overwrite warning
- Korean and English UI copy based on the system language

## Screenshot

![VaultSync screenshot](docs/screenshot.png)

## How It Works

VaultSync keeps a hidden base repository under:

`~/Library/Application Support/VaultSync/Repos/<target-id>.git`

The selected vault folder is attached to that repository as a linked `git worktree`.

When files inside the vault change, VaultSync:

1. Waits briefly for file activity to settle
2. Creates a local Git commit when needed
3. Pushes the current branch to the configured remote repository

If `Allow remote overwrite` is enabled, VaultSync will use force push. This can replace files that already exist in the remote repository.

## Build

Requirements:

- macOS
- Xcode 16 or newer

Build from Xcode:

1. Open `GitSync.xcodeproj`
2. Select the `GitSync` target
3. Set your signing team if needed
4. Build and run

Build from the command line:

```bash
xcodebuild \
  -project GitSync.xcodeproj \
  -scheme GitSync \
  -configuration Debug \
  -derivedDataPath /tmp/GitSyncDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Usage

1. Launch the app
2. Click the menu bar icon
3. Press `Add Vault`
4. Enter the remote repository URL
5. Choose the local vault folder
6. Decide whether remote overwrite should be allowed
7. Finish setup

After setup, VaultSync watches the folder and pushes local changes to the remote repository.

## Privacy

- Personal default paths and personal remote URLs are not hardcoded
- Per-user Xcode workspace data is ignored via `.gitignore`
- The hidden Git base repository is stored in the current macOS user's Application Support directory

## Third-Party Software

- `git-sync` by Simon Thum and contributors
  - Source: <https://github.com/simonthum/git-sync>
  - License: CC0

## License

This project is licensed under the MIT License.

See [LICENSE](LICENSE) for the full text.
