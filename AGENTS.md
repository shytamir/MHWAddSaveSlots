# Repository instructions

Read this file before changing the repository, including untracked files.

## Purpose

Build an experimental REFramework mod for Monster Hunter Wilds that creates and loads additional characters using its own selector. Support both independent clones and fresh characters, preserve a native-range persisted selection, retain verified expanded-save backups, and provide explicit trimming to three entries. The native three-row menu is not the target. Do not substitute external save swapping for native expanded records.

## Save safety

- Develop and test against verified copies of the user's saves. Never run experiments on the originals.
- Keep personal saves, account identifiers, runtime dumps, test-session journals, and binaries out of Git.
- Before substituting a test save directory, close Wilds and Steam, verify Steam Cloud is disabled for Wilds, and use Steam Offline Mode.
- Preserve the original directory intact, record hashes, journal the substitution, and provide a recovery path before launching the game.
- Restore the original directory after testing and verify its contents against the recorded hashes.
- Experimental mutation must be explicitly enabled for an isolated test session; default operation is read-only discovery.
- The user handles Steam and all in-game controls. Do not launch, close, or automate those applications.
- Keep expanded recovery snapshots after trimming or an unclassified save change. Never overwrite the only expanded backup with a smaller container.

## Implementation and evidence

- Inspect the installed REFramework API and current game types before choosing hooks. Do not assume offsets or APIs from other RE Engine games apply to Wilds.
- Prefer managed calls and verified type metadata over raw memory patches.
- Perform game mutations on an appropriate game callback, not directly in the UI drawing callback.
- Report static inspection, mocked tests, and actual in-game results separately. A larger array alone does not prove loading or persistence.
- Document the tested game build and REFramework revision, prerequisites, installation, removal, recovery, and remaining limitations in README.md.
- Run focused checks for changed behavior. Do not commit or push without a user request.
