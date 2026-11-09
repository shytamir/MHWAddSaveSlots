# MHWAddSaveSlots

Experimental REFramework mod for additional **Monster Hunter Wilds** characters, selected through its own overlay. Expanded records remain in the native `data001Slot.bin`; the native three-row menu assets are unchanged.

The current implementation supports **3–16 entries**, independent clones, empty entries for the native new-character flow, a native-range persisted selection, versioned save backups, and an explicit conversion back to three entries. Sixteen is a conservative implementation limit, not a measured engine limit.

**Use verified copies only.** Live testing has created a fourth clone and a fresh fifth character, played the fifth character's tutorial, saved, fully restarted, and loaded the fifth character with its appearance and progress intact. Five-entry backups passed file-hash verification. Trimming completed successfully; the resulting three-entry copy booted, displayed the native three, and loaded/saved the first character with this mod absent. Capacities 6–16 have not been played. See [validation](docs/safeguards-validation.md) for the separate runtime and mocked evidence.

## Environment and requirements

Original live testing on 2026-11-09 used:

| Component | Version |
| --- | --- |
| Game | Windows Steam `1.042.00.03` |
| Steam build | `25921695` |
| REFramework | `v1.5.9.1+514`, built 2026-10-11 |
| REFramework revision | `d052e8fd3fd41d0a1a33394fcf6e6c19be39b1ee` |

Other builds and clean installations have not been validated. Existing unrelated mods were present during the original tests. The REFramework DLL is not distributed or replaced.

Requirements: PowerShell **7+** for the backup companion, Steam Cloud disabled, Steam **Offline Mode**, sufficient disk space for retained snapshots, and an isolated whole-app userdata copy. The user operates Steam and the game manually. Clones retain their source's online identifiers; unique identity generation for clones and multiplayer use are outside scope. Fresh entries use the game's initializer and character editor rather than copied progression; this path completed a live fifth-character round trip.

## Install and prepare

With Wilds closed, copy the loader and **all** modules into the game:

```text
reframework/autorun/MHWAddSaveSlots.lua
reframework/autorun/MHWAddSaveSlots/
    control.lua
    policy.lua
    records.lua
    compat.lua
    poc.lua
    probe.lua
```

Restart the game after script changes. Hot reload is intentionally unavailable while stateful save hooks may have outstanding transactions. Without an armed isolated session at startup, hooks are inactive and operations remain read-only.

Disable Cloud for Wilds, set Steam Offline Mode, and fully exit Wilds and Steam. Closing Steam's window is insufficient. Start with ordinary three-entry saves whose capacity is known.

```powershell
.\scripts\SaveSandbox.ps1 -Action Prepare `
  -SessionDirectory 'D:\save-tests\session-001' `
  -AppDirectory 'C:\Program Files (x86)\Steam\userdata\ACCOUNT\2246340' `
  -GameDirectory 'C:\Program Files (x86)\Steam\steamapps\common\MonsterHunterWilds' `
  -CloudDisabled -SteamOffline

.\scripts\SaveCompanion.ps1 -Action Initialize `
  -SessionDirectory 'D:\save-tests\session-001' -Slots 3

.\scripts\SaveSandbox.ps1 -Action Arm `
  -SessionDirectory 'D:\save-tests\session-001'

.\scripts\SaveCompanion.ps1 -Action Watch `
  -SessionDirectory 'D:\save-tests\session-001'
```

Prepare preserves the original directory intact, copies and verifies every file, and journals recovery paths. `-CloudDisabled` and `-SteamOffline` confirm settings already made by the user; they do not change Steam. Initialize creates a verified baseline backup; **`-Slots` is a known starting capacity supplied by the operator, not a count decoded from disk**. Do not initialize an unknown or truncated container with an assumed expanded count.

Leave Watch running throughout the game session and restarts. It only reads active save files; its writes go to the backup store and REFramework control JSON. Start Steam manually, recheck Offline Mode, then launch Wilds. The 12-hour lease authorizes creation and trim actions. Preservation hooks remain active for an already armed process if that lease expires, but the next launch must be armed again. Never reset scripts, remove the marker, or change save directories while Wilds is running.

## Select, clone, or create a fresh character

1. Open **Start Game / Select Saved Data**, then press **Insert** to open REFramework before clicking the custom selector. Its controls are disabled while REFramework is closed to avoid sending the same click to the underlying native menu. The custom overlay lists every allocated entry.
2. For a clone, choose its source and names, then **Add independent clone**. The source must be occupied. Creation audits the managed object graphs for shared mutable objects before attaching the clone.
3. For fresh progression, choose **Add empty entry for a fresh character**, then **Create new in…** on that entry. This calls the game's factory and initializer, verifies that the record is inactive, and passes the empty index through the native selection completion flow. Complete the normal character editor yourself. An empty allocation alone is not a successfully created character.
4. Load the desired occupied entry through the custom selector. Save normally in game and wait for **backup verified** before restarting or making another test change.
5. Restart with the companion running and the same armed session. Check that each extra character is populated and loads without cloning it again.

Creation does not overwrite or reorder existing records. Cancelling the native editor can leave an empty allocated entry; reuse its Create new button. Arbitrary deletion/reordering is not implemented. The first three entries can still be selected through the normal menu.

## Persistence and backups

The live `CurrentUserDataIndex` can exceed 2. The separate `cSystemCommonParam.LastUserIndex` is repaired to `0–2` on the objects used for system-save serialization, including staging copies. The fallback is the last observed native selection, or 0. Repairs never change the live character index.

Save-copy destinations grow to the source capacity. Startup destinations use the capacity of the companion's last verified save snapshot. Capacity is committed only after a matched native save execution/completion and a hash-verified file copy. Separate start/end receipt files survive process exit and replacement of the runtime heartbeat. The native character file's write time must fall within that request's receipt interval; a later write cannot be attributed to an old completion. Capacity is not increased merely because a new array was allocated.

Snapshots live under `SESSION/backups/snapshots/<id>/app`, with SHA-256 manifests. They are never automatically overwritten or pruned. The companion retains the latest expanded recovery point even after a valid trim. It verifies the active character-file hash against its ledger before authorizing startup. Untracked changes, including saves made with the mod absent, are retained as **unclassified** snapshots and block mutations; they cannot silently become an expanded recovery point.

The save gate requires a fresh companion heartbeat and acknowledgement of the previous completed character save, including one from the previous process. A startup load waiting for that acknowledgement is deferred and retried when the backup is ready. If backups fail or the companion stops, another character save is refused instead of overwriting the only unarchived result. The game may display a save error: keep the game open, inspect the companion, and retry only after it reports ready. System-save index repair continues while the character backup completes. A disk snapshot verified by hash is evidence of byte preservation; it is not an independent decode of every character field.

## Trim to three entries

1. Load one of the **first three characters** and wait for the normal save flow to finish.
2. In REFramework's **Script Generated UI → Wilds expanded characters**, choose **Prepare trim: save and back up all characters**.
3. Wait for trim status **ready**. This requires a new successful expanded save and a verified backup.
4. Choose **Confirm trim to three characters**. The companion durably journals the expanded snapshot before the live array can shrink.
5. The mod retains entries 1–3 by reference, requests the game's normal save, and waits for the resulting three-entry snapshot to be verified. Wait for trim status **complete**.
6. Exit and restart the copied-save test without this mod to validate native compatibility before using the export elsewhere. Keep the expanded snapshot and its manifest.

Trimming uses the game's serializer; it does not cut bytes from an encrypted file. If a trim save fails, the retained expanded array is restored in memory and the session reports a fault. A crash or untracked partial write blocks automatic promotion of that file. Inspect the journal and retained snapshots before trying another launch. The conversion is not an atomic transaction across the game's system and character files.

## Recovery, export, and removal

To inspect the backup ledger or export an immutable snapshot to a **new** directory:

```powershell
.\scripts\SaveCompanion.ps1 -Action Status -SessionDirectory 'D:\save-tests\session-001'
.\scripts\SaveCompanion.ps1 -Action Export `
  -SessionDirectory 'D:\save-tests\session-001' `
  -Snapshot 'SNAPSHOT_ID_FROM_LEDGER' -Destination 'D:\save-recovery\export-001'
```

Export verifies all files and copies them with their manifest. It refuses existing destinations, active save paths, preserved originals, and the backup store. A snapshot whose capacity is 0 is unclassified and must not be enrolled as an expanded save. To investigate an expanded export, prepare another isolated test session with Wilds and Steam closed, preserve that session's starting copy, and use the verified export with its recorded capacity. Never experiment on the ordinary originals.

Backups are complete app snapshots. Restoring an older whole snapshot rolls back its native characters too. **Automatic merging of archived extras with newer native-character progress is not implemented.** Retain both versions; do not blindly replace newer native progress. The mod detects this situation and preserves recovery data rather than claiming a lossless merge.

After testing, fully exit Wilds and Steam yourself, then restore the ordinary originals:

```powershell
.\scripts\SaveSandbox.ps1 -Action Restore -SessionDirectory 'D:\save-tests\session-001'
```

Restore retains the experimental directory as `2246340.mhw4-result-<id>`, restores the original directory, verifies every original hash, and disables mutations. The companion stops when the session leaves the isolated stage. Keep Cloud disabled until restoration succeeds.

If interrupted, use `SaveSandbox.ps1 -Action Status` with the same session path. The journal gives exact paths. With both applications closed, preserve the active experimental directory, rename the journal's original directory back to active, and verify it against `original-sha256.json`. Do not overwrite preserved originals with test files or accept a Cloud conflict over them.

Only remove the loader and its module folder after restoring ordinary saves or validating a trimmed copy. Keep the backup store and manifests. Leave the REFramework DLL and unrelated mods untouched. Runtime JSON, save files, account data, binaries, and journals stay outside Git.

## Evidence and checks

The original four-character implementation (commit `3b1cc0c`) cloned Gupta/Kirikau, audited 76,760 mutable objects on each side with zero shared objects, entered the Grand Hub, saved, and loaded the fourth record in a fresh process. A native-range startup followed by saving with the mod absent shrank the file from 858,988 to 595,260 bytes, strongly indicating loss of that fourth entry; see the [absence test](docs/native-compatibility-test.md).

Focused checks for the new implementation:

```powershell
.\scripts\Test-SaveSandbox.ps1
.\scripts\Test-SaveCompanion.ps1
lua tests/test_safety.lua  # Lua 5.3+; Fengari also supported
git diff --check
```

Tests cover index separation, 5/16-entry destination growth, fresh initialization, backup acknowledgement gates, trim preparation and confirmation, unchanged native references, immutable expanded snapshots, replay, wrong-session data, corruption, and unclassified saves. An optional `-CopiedSaveDirectory` on Test-SaveCompanion checks exact byte preservation using another copy of retained saves; it does not run the game. The installed safety hooks use this build's named methods and named success enum constants, failing initialization when required metadata is unavailable.

Long-term progression, every game save path, capacities above five, and an expanded five-entry boot with this mod absent need further validation. The successful absence test for this implementation used its trimmed three-entry result; the earlier four-entry absence test used a manually selected native index. The user reported minor creation-screen visual artifacts of unknown cause. [Current validation record](docs/safeguards-validation.md) separates observed results from mocks. No claim of universal save safety or game-version compatibility is made.

## References

- [REFramework Lua SDK](https://refdocs.praydog.com/api/sdk.html)
- [REFramework thread-local hook storage](https://refdocs.praydog.com/api/thread.html)
- [Installed revision's managed-array implementation](https://github.com/praydog/REFramework/blob/d052e8fd3fd41d0a1a33394fcf6e6c19be39b1ee/shared/sdk/SystemArray.cpp)

Apache-2.0; see `LICENSE`. Game files, personal saves, and third-party mods are not included.
