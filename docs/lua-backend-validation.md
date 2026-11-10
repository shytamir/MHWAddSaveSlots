# Add Save Slots — Lua backend validation, 2026-11-10

## Release status

The author reported publication of **Add Save Slots 1.0** on [Nexus Mods](https://www.nexusmods.com/monsterhunterwilds/mods/5329) on 2026-11-10. The repository is now in [maintenance mode](../MAINTENANCE.md). Relative to the live-tested `0.3.0-dev.2` ZIP, the release changes are display strings, documentation, and package metadata; save behavior is unchanged. Setup wording asks for a separate backup rather than asserting a copied-save test condition. Activation, the three-slot enrollment check, and preservation hooks are unchanged. The package contains the player README, license, Lua files, and manifest; investigation and validation reports stay in the repository. It integrates the earlier native-record selector with the engine serializer and in-process archive, and fixes character initialization during recovery. The native three-row menu remains unchanged. No PowerShell runtime, companion process, or additional DLL is included. Development version names below identify the artifacts actually tested; they are not current installation instructions.

The focused live restore/load/save/restart test passed on 2026-11-10 after correcting the raw reconstruction path. The user opened Steam in Offline Mode and authorized computer control. A development harness restored a disk snapshot into slot 3 of a verified native three-character copy. The integrated archive/selector package was not installed for this test.

## Live snapshot recovery

1. Direct deserialization produced identical bytes but the game crashed after selecting the restored character, before gameplay. The user confirmed it closed on its own. Windows recorded an access violation (`c0000005`, executable offset `0x206f6f`); this did not establish the exact missing runtime field.
2. The native `cUserSaveParam.create`, `init`, and `copyFrom(ace.cSaveDataBase)` path produced an initialized object. Its serialization initially differed, so the harness refused attachment. Offline comparison isolated the difference to `_StartMenu.RecentMenu` and `_StartMenu.FavoriteMenu`, which `copyFrom` left zeroed. A separate detached `setupAfterLoad` experiment threw and was removed from the probe; it is not the recovery path.
3. Copying those two arrays' contents into the arrays already allocated by `init` yielded all **3,876,896 snapshot bytes exactly**. Only the copied target slot was replaced; the first two record references were retained. The restored character reached Grand Hub gameplay with the expected visible equipment and palico.
4. Native manual Save completed successfully, followed by native Save and Quit and a verified process exit. The user-save callback reported `EXECUTE_RESULT.SUCCESS = 1` and `ERROR_TYPE.NONE = 0`.
5. A new process started with the restore harness explicitly **observation-only**. Slot 3 showed the restored character and increased playtime, then loaded into Grand Hub gameplay again. Runtime reports confirmed index 2, `app.IngameState`, the expected character, and a further successful native save callback. No snapshot was reattached on this boot.

The production codec now uses the same initialized-copy and menu-preservation sequence and refuses to return the record if any serialized byte differs. This demonstrates one snapshot's recovery and persistence, not exhaustive field coverage or integration of every archive/save hook. The normal restart test used Save and Quit. After the final successful reload, injected menu keys were ineffective; Steam's Stop control closed that completed session while the save service was idle.

Cleanup restored and hash-verified all **41 original files**, retained the test save separately, removed the temporary autorun, restored the previously installed loader byte-for-byte, and disabled mutation. Personal snapshots, logs, and session journals remain outside Git.

## Existing live evidence

### Completed package test

The exact `0.3.0-dev.2` ZIP was installed onto a fresh, verified copy of the original three-character save on 2026-11-10. Steam Cloud was disabled and Steam remained in Offline Mode to isolate that test session; neither setting is a runtime requirement of the mod. Cloud synchronization and online play were outside this test's coverage. Setup used the normal package confirmation UI; no companion or mutation harness was running. A separate read-only observer recorded character names, active/current indexes, persisted selection, and save-service state. Other previously installed mods remained present.

- UI activation captured and read-back verified the initial three-character archive.
- A slot-4 clone, Gupta with Kirikau, reached Grand Hub gameplay. Native manual save succeeded, then a full process restart and another load reached Grand Hub again.
- A genuinely empty slot 5 entered native character creation. The user completed Atpug and Uakirik and advanced into the opening tutorial. Native five-entry saves completed with result `1`, error `0`, and committed archives.
- The serialized records for the first four characters were byte-for-byte identical before fresh creation and after the tutorial save; the fifth record changed as expected.
- Atpug and Uakirik survived a full process restart and loaded at the saved tutorial checkpoint. Another five-entry native save succeeded. The restart used Steam Stop after successful save completion and an idle save service, because injected input could not reliably complete the mandatory tutorial prompt. This is not evidence of normal Save and Quit for the fresh character.
- The active runtime indexes were `3` and `4` for the extra characters while the persisted selection remained `0`.
- With Alex2 loaded, the packaged two-step trim reached `ready`, then `complete`. The native trim write reported result `1`, error `0`, and three entries. The five-entry source archive remained present. Native Save and Quit then completed another three-entry write and the process exited.
- With the package loader removed, a new process showed all three native rows and no expanded selector. Alex2 reached Grand Hub gameplay. Native manual Save returned to the menu without an error and updated the save files; native quit ended the process. Reinstalling the loader loaded three entries, retaining Alex2's increased playtime and the older expanded archives.

- After reinstalling the loader, the archive UI restored Gupta/Kirikau from the retained five-entry pre-trim snapshot into entry 4 of the current three-entry save. Gupta reached Grand Hub, a native four-entry save succeeded, and native Save and Quit completed with result `1`, error `0`, followed by process exit.
- A new process loaded Gupta/Kirikau from the native save without another archive restore. Grand Hub gameplay and a further four-entry save succeeded; the active index was `3` and the persisted index remained `0`. The user subsequently closed Wilds and Steam; the final shutdown report recorded another completed four-entry save.
- Comparing the snapshot immediately before recovery with the first native save afterward found that the first three characters' `_StartMenu.RecentMenu` and `_StartMenu.FavoriteMenu` arrays had become zeroed. All serialized bytes outside those two arrays were identical for each native character. This is an accepted known limitation, not evidence that every field was preserved. The reset boundary within recovery/load/save has not been isolated. The codec's exact detached reconstruction check alone does not cover later native copies.

Cleanup restored and SHA-256 verified all **41 original files**, restored all **seven previously installed mod files** against their manifest, removed the read-only observer and test activation, and disabled the isolation/mutation marker. The test userdata directory, full archive, separate five-character export, and evidence remain private and outside Git.

At eleven snapshots, the archive occupied 242,065,306 bytes; one five-character snapshot was 25,696,457 bytes. This is a storage observation, not a save-latency benchmark.

- The earlier backend created and loaded a fourth clone and a fresh fifth character. The fifth character's appearance and tutorial progress survived a full restart.
- The earlier backend's trim to three entries passed a subsequent mod-absent native load/save test.
- Wilds `1.042.00.03`, Steam build `25921695`, REFramework `d052e8fd3fd41d0a1a33394fcf6e6c19be39b1ee` serialized a copied character to 3,876,896 MessagePack bytes.
- The engine reconstructed a detached object and produced identical bytes; the live source serialization stayed unchanged. A disk snapshot decoded in 4,096-character Base64 chunks reproduced the bytes exactly.

The packaged test demonstrates these workflows on one installation with its other mods present. It is not exhaustive gameplay or field-preservation validation. Details and primary-source prior art are in [the investigation](save-byte-investigation.md).

## Automated checks

- `tests/test_archive.lua`: 18 assertions covering checksum vectors, malformed records, immutable archives, pending expanded capacity, committed trim capacity, retention of expanded records, partial publication, write failure, snapshot corruption, commit corruption, and path rejection.
- `tests/test_preservation.lua`: 27 assertions covering native/live index separation, pre-write snapshots, successful commit, refusing writes on serialization failure, explicit trim, restoring into an extra slot without replacing native entries, commit failure, interrupted-save startup capacity, corrupt activation, missing backup data, native inspection when preservation is unavailable, and smaller native loads with reserved empty extra slots and retained recovery data.
- Existing `tests/test_safety.lua`: all 52 earlier assertions retained; the selector now receives its backend explicitly.
- `tests/test_snapshot_codec.lua`: 12 assertions covering initialized-object return, exact serialization, retaining distinct initialized menu arrays, and refusing factory failure, copy rejection, array-layout changes, lost serialized fields, wrong types, and malformed input.
- Lua syntax checks passed for the production modules. The package builder verifies an explicit file allowlist and the SHA-256 of every source/document file inside the ZIP.

These are mocked/storage checks. They do not measure game-thread latency, native serializer field coverage, or gameplay recovery.

### Maintenance transition checks, 2026-11-10

After relocating developer diagnostics, companion tools, and historical reports, all 109 Lua assertions and both PowerShell fixture suites passed. Syntax checks covered all 21 Lua files and six PowerShell files; all 29 relative Markdown links resolved. The legacy test still exercises the current selector with its original companion-backed mock assertions.

A separate package build retained the exact eleven-entry allowlist. All ten packaged source/document files were byte-for-byte identical to the retained 1.0 archive; the original archive's SHA-256 remained `412486db089b36ce21ef53fb7d497ff60b1dbd36546d33eaa8766b070f279f98`. No player README or runtime behavior changed. These were repository and synthetic-fixture checks; no game session, installed mod files, or personal saves were used for this cleanup.

## Validation coverage and follow-up

1. **Passed:** focused snapshot recovery and packaged archive recovery both reached gameplay, native save, full process restart, and reload.
2. **Passed with the shutdown qualification above:** fresh-copy installation, normal UI enrollment, clone and fresh creation, save, and restart with no companion running.
3. **Passed with a known limitation:** trim, mod-absent native load/save, and archived-extra recovery. Native records retained identical serialized data outside their reset recent/favourite menu arrays. Isolate that boundary and check menu preservation on a future copied-save run.
4. **Mocked only:** interrupted publication/commit and missing/corrupt backup data. Exercise these conditions in the game before claiming robust failure recovery.
5. Measure save-time pauses and archive growth with five and sixteen entries, and verify large saves and a second installation. A normal Save and Quit from the fresh tutorial character also remains unverified in this packaged run.

The archive uses read-back equality plus FNV-1a checksums for accidental corruption detection. It is not an authenticated format. It preserves serialized character objects, not every file in Steam userdata or the complete system-save container. Keep a separate whole-directory backup.
