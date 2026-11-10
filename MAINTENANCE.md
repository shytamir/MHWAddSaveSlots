# Add Save Slots maintenance

Add Save Slots 1.0 is published on [Nexus Mods](https://www.nexusmods.com/monsterhunterwilds/mods/5329), as reported by the author on 2026-11-10. The repository is in maintenance mode: address reproducible bugs, save integrity, game/REFramework compatibility, and documentation. New features require a separate explicit request. There is no active feature roadmap or promise of compatibility with future game updates.

Player instructions and the save-data-loss disclaimer remain in [README.md](README.md). This document and the reports linked below are maintainer material and are excluded from the player package.

## Released baseline

| Item | Baseline |
| --- | --- |
| Player version | 1.0 |
| Published mod page | [Add Save Slots on Nexus Mods](https://www.nexusmods.com/monsterhunterwilds/mods/5329) |
| Final local release package | `AddSaveSlots-1.0.zip`, prepared from `e54dffd` |
| Package SHA-256 | `412486db089b36ce21ef53fb7d497ff60b1dbd36546d33eaa8766b070f279f98` |
| Existing Git tag | `1.0` at `9e5c75327e1b7a5b97bef81dd683c5814c99c31c` |
| Live-tested game | Wilds `1.042.00.03`, Steam build `25921695` |
| Live-tested REFramework | `d052e8fd3fd41d0a1a33394fcf6e6c19be39b1ee` (`v1.5.9.1+514`) |

The tag predates the final player-documentation and package-naming cleanup. Preserve it; do not retag it to disguise that difference. The hash identifies the local release handoff archive, not an independently downloaded Nexus asset. The released runtime is Lua-only and has no companion or additional DLL dependency.

## Repository map

| Path | Purpose |
| --- | --- |
| `reframework/autorun/` | Released loader and seven Lua modules; keep existing internal names and data paths compatible. |
| `tests/` | Mocked Lua regressions for the archive, codec, preservation, selector, and legacy safeguards. |
| `scripts/Build-Package.ps1` | Explicit package allowlist and per-file SHA-256 verification. |
| `scripts/SaveSandbox.ps1`, `scripts/Test-SaveSandbox.ps1` | Developer copied-save isolation and fixture checks. |
| [scripts/diagnostics](scripts/diagnostics/README.md) | Manual engine investigation and restore harnesses; never ship or deploy automatically. |
| [legacy/companion](legacy/companion/README.md) | Retained companion prototype and regressions; not the released backend. |
| [docs/lua-backend-validation.md](docs/lua-backend-validation.md) | Detailed live evidence, mock coverage, and unresolved limits. |
| [docs/save-byte-investigation.md](docs/save-byte-investigation.md) | Engine API investigation and prior art. |
| [docs/history](docs/history/README.md) | Superseded companion documentation and earlier test reports. |
| `work/`, `outputs/` | Ignored local tooling, fixtures, evidence, and build artifacts. These can contain private data; do not commit or indiscriminately clean them. |

Personal saves, archives, account identifiers, test-session journals, runtime dumps, and third-party binaries remain outside Git. Housekeeping must not remove recovery data or modify installed game files.

## Compatibility and known limits

- Live evidence covers a fourth clone, a fresh fifth character, save/restart/reload, trimming to three, a mod-absent native load/save, and archived-extra recovery followed by save/restart/reload. The integrated live package was `0.3.0-dev.2`; the 1.0 branding and documentation changes did not alter save behavior.
- Recovery/load/save can reset the first three characters' recent/favourite menu arrays. The observed native records were otherwise byte-identical. The exact reset boundary remains unresolved; do not claim complete field preservation.
- The implementation caps entries at sixteen. Live testing reached five; capacities six through sixteen are not live-validated. Long-term progression, a second installation, and save-time pauses remain unmeasured.
- Interrupted writes, corrupt/missing archives, and commit failures have mocked coverage, not complete in-game fault-injection coverage. Archives grow without automatic pruning and preserve characters, not the whole Steam userdata directory.
- The fresh character survived restart at the tutorial checkpoint, but that restart followed a successful save and Steam Stop. Normal Save and Quit for that fresh-character run remains unverified. Other installed mods were present during testing.
- Offline Mode and disabled Steam Cloud were isolated test conditions, not mod requirements. Online play and Cloud synchronization were outside the live test coverage.

These are evidence limits and maintenance candidates, not commitments to add features or guarantees of save safety. Read the full validation report before making stronger claims.

## Handling a report

Collect the mod version, game/Steam build, REFramework revision, action attempted, slot count, exact error, other relevant mods, and whether a separate backup exists. Ask for redacted logs and reproduction steps; do not ask users to upload personal saves, entire archives, or account identifiers to a public issue. Preserve the reported save and backup state before investigating.

Reproduce mutations only on verified copies. Follow the isolation, hashing, journaling, and restoration rules in [AGENTS.md](AGENTS.md). Game/REFramework updates require checking current type metadata and APIs before changing hooks. Check prior art and existing framework capabilities before inventing replacements. Historical companion assumptions do not constrain future fixes.

## Focused checks

Run from the repository root with Lua 5.3+ (Fengari is also supported) and PowerShell 7 for the PowerShell tools:

```powershell
lua tests/test_archive.lua
lua tests/test_preservation.lua
lua tests/test_snapshot_codec.lua
lua tests/test_safety.lua
pwsh -NoProfile -File scripts/Test-SaveSandbox.ps1
pwsh -NoProfile -File legacy/companion/Test-SaveCompanion.ps1
git diff --check
```

The Lua baseline is 109 assertions: 18 archive, 27 preservation, 12 codec, and 52 selector/legacy safeguards. Check the printed PASS/assertion output as well as the exit status; some Lua runners do not return failure reliably. The PowerShell checks create synthetic fixtures under ignored `work/sandbox-fixtures`; no live game or personal save is needed. Keep these tests rather than replacing them merely to remove PowerShell from developer tooling.

Run checks appropriate to each change. Hook, serialization, loading, or save behavior changes also need focused live copied-save validation before being described as runtime-tested. Documentation and layout changes do not require launching the game. Record automated and live results separately.

## Preparing a maintenance release

1. Document the concrete fix and its evidence. Update player instructions only where behavior or limitations change; keep test history and development version names out of the package.
2. Run the relevant checks. Inspect the diff for private files, unrelated changes, and unintended runtime changes.
3. Choose a new version for an actual release, update the player version and builder default together, and build into a new output directory:

   ```powershell
   pwsh -NoProfile -File scripts/Build-Package.ps1 -Version X.Y.Z -OutputDirectory outputs/release-X.Y.Z
   ```

4. Verify the builder's allowlist and hashes. Only the player README, license, eight runtime Lua files, and package manifest belong in the ZIP. Keep a separate checksum. Do not include diagnostics, legacy tools, tests, private data, or development reports.
5. For a behavior change, validate the exact candidate on copied saves: activation, the affected workflow, normal save, process restart, and reload. Include clone/fresh creation, archive recovery, and trim/mod-absent compatibility when the change can affect them. Restore and hash-verify the originals afterward.
6. Commit and push only when authorized. New tags, GitHub releases, and Nexus uploads require the author's release instruction; never silently overwrite an existing tag or published archive. Record the new commit, package hash, compatibility baseline, and evidence limits here when releasing.

For housekeeping checks, build into a disposable, unique directory under `work/` and compare the package inputs with the released archive. Do not replace `outputs/AddSaveSlots-1.0.zip`. Repository maintenance alone does not change the released version.
