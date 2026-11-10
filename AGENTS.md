# Repository instructions

Read this file before changing the repository, including untracked files.

## Purpose and maintenance scope

Maintain Add Save Slots, the released REFramework mod for Monster Hunter Wilds. Read MAINTENANCE.md for the release baseline, repository layout, validation coverage, and release procedure. Prioritize reproducible bugs, save integrity, compatibility updates, and documentation. Start feature work only when explicitly requested; historical prototypes are evidence, not binding architecture decisions.

The current mod supports independent clones and fresh characters in native expanded records, a native-range persisted selection, verified Lua character archives, and explicit trimming to three entries. The native three-row menu remains unchanged. Players do not need a companion process, PowerShell, or an additional native DLL. Keep obsolete companion code under legacy/ and developer probes under scripts/diagnostics/, outside the package allowlist.

## Save safety

- Develop and test against verified copies of the user's saves. Never run experiments on the originals.
- Keep personal saves, account identifiers, runtime dumps, test-session journals, and binaries out of Git.
- For isolated development tests, before substituting a test save directory, close Wilds and Steam, verify Steam Cloud is disabled for Wilds, and use Steam Offline Mode. These are test-isolation conditions, not requirements for using the released mod.
- Preserve the original directory intact, record hashes, journal the substitution, and provide a recovery path before launching the game.
- Restore the original directory after testing and verify its contents against the recorded hashes.
- Developer probes must default to read-only discovery; experimental mutation requires an explicitly armed, isolated copied-save session. Preserve the released mod's explicit backup confirmation before activation.
- The user handles Steam and in-game controls unless they explicitly authorize computer control for the current work.
- Keep expanded recovery snapshots after trimming or an unclassified save change. Never overwrite the only expanded backup with a smaller container.

## Implementation and evidence

- Inspect the installed REFramework API and current game types before choosing hooks. Do not assume offsets or APIs from other RE Engine games apply to Wilds.
- Prefer managed calls and verified type metadata over raw memory patches.
- Perform game mutations on an appropriate game callback, not directly in the UI drawing callback.
- Report static inspection, mocked tests, and actual in-game results separately. A larger array alone does not prove loading or persistence.
- Keep README.md and the package player-facing: installation, use, recovery, removal, limitations, and the strong save-data-loss disclaimer. Do not include prototype version history, development instructions, or test conditions there.
- Record tested game/REFramework versions and evidence limits in MAINTENANCE.md and the repository validation reports. Preserve historical evidence without presenting it as current release behavior.
- Use the existing PowerShell development tools and tests where useful; their language is independent of the Lua-only runtime. Check prior art and available REFramework features before engineering replacements.
- Keep published tags and release archives immutable. Repository housekeeping alone does not warrant changing the mod's version or rebuilding a published asset in place.
- Run focused checks for changed behavior. Do not commit or push without a user request.
