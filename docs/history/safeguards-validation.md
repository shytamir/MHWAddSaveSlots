# Expanded-character safeguards: validation

Historical companion-backend evidence. For the released Lua backend, see [the integrated validation report](../lua-backend-validation.md).

Implementation and live testing: 2026-11-09, with recovery completed on 2026-11-10 (Europe/Madrid). Target game and REFramework versions are listed in the [historical companion guide](legacy-companion.md).

## Completed outside the game

- Lua policy and mocked managed-hook tests: native-range persisted selection with an unchanged live index, five/sixteen-entry save-copy destinations, fresh factory/initializer without copying, save acknowledgement gate, stale and wrong-session rejection, and a two-stage trim that retains the first three object references.
- Synthetic filesystem tests: immutable snapshots, explicit trim journal, retained expanded recovery point after a three-entry result, duplicate completion handling, unclassified writes, wrong session, and corrupt snapshot rejection.
- Backup byte check against an additional copy of the retained expanded test directory: all 41 source files remained unchanged and every snapshot hash matched.
- Existing sandbox checks: verified copying, explicit arming, retaining test results, restoring original hashes, and idempotent recovery.

These tests do not execute Wilds. Synthetic slot counts are test inputs. Actual save format decoding and per-character semantic comparison are not performed by the companion.

## Live validation

The first startup reached Select Saved Data with three records and both indices at 0. Named success/error enums resolved. It also exposed a real startup save that bypassed the `requestSave` convenience hook: the execution callback arrived without a tracked event. The companion retained the changed three-entry file as unclassified and blocked further mutations. No additional character had been created. This was a failed safety-path test, not a successful save-gate validation.

The gate was moved to `cSaveRequest.execMainFunction`. Static inspection confirmed this virtual method starts the save service and returns `ERROR_TYPE.UNKNOWN` on a refused start; the manager records a nonzero execution error as failure. Request object identities now pair execution and completion. Added mocks cover direct execution without the convenience call and distinguish load callbacks. The user also reported tiny text; the selector now uses a 28-pixel font.

On the second live startup, the same native save path produced a tracked three-entry completion (`SUCCESS`, `NONE`), the companion acknowledged its verified snapshot, and no mod fault was reported. This validates that startup path with the revised gate; expanded saves, fault injection, trimming, and fresh-character creation remain separate tests.

The user confirmed the larger text was readable. An initial click-through loaded the first native character; the fourth clone was nevertheless present and a four-entry snapshot was verified. With REFramework open, the user then confirmed Gupta loaded. Runtime evidence showed `app.IngameState`, current index 3, and `LastUserIndex` 0; the repair counter increased and four-entry native saves received successful completions and companion acknowledgements.

A full exit/relaunch exposed another failure: the final user-save completion still had a busy runtime flag, then the new process replaced that runtime file before backup acknowledgement. Startup blocked on the changed character file. Earlier verified expanded snapshots remained intact. The implementation now writes separate durable execution/completion receipts and resumes deferred loads after verification. A synthetic regression covers the completed save with an immediately replaced runtime heartbeat.

After that fix, the user relaunched successfully, created a **fresh fifth character**, completed the tutorial hunt, saved, and returned to character selection. The native creation process ran smoothly and the user's appearance choices were preserved on entering gameplay. The user observed minor visual artifacts during creation; their cause is unknown and has not been attributed to this mod.

The resulting runtime snapshot contained five active entries: all three native characters, the fourth clone, and the new fifth character. Current index was 4 while `LastUserIndex` was 0. Native five-entry save completions reported `SUCCESS`/`NONE`; the companion acknowledged the final receipt and its five-entry snapshot passed full file-hash verification. The system field value was observed in memory, not independently decoded from disk.

The user then fully exited and relaunched Wilds, selected the existing fifth character without recreating it, and confirmed that the character, appearance choices, and tutorial progress were intact in gameplay. A new runtime ID, five active records, `app.IngameState`, current index 4, and `LastUserIndex` 0 were recorded. Further five-entry saves completed and were acknowledged. A separate export of the verified five-entry snapshot was retained before trimming. This establishes the fresh fifth-character create/save/full-restart/load round trip on this build.

The user loaded the first native character, prepared the expanded backup, confirmed the trim, and observed **Trim: Complete** with no errors. Runtime and receipt evidence showed a successful three-entry native save; the companion completed the trim transaction, acknowledged that receipt, and retained the verified five-entry source snapshot. All 41 files in each snapshot passed independent hash verification. The character container changed from 858,988 to 595,260 bytes. Native slot references were preserved by the implementation; the resulting runtime contained the three expected active native identities at current index 0.

With Wilds closed, all seven mod Lua files were moved out of autorun and hash-verified. The user relaunched, checked the native three and the absent selector, loaded the first native character, saved, and closed the game, reporting no observable issues. The new run's REFramework log contained 18 script-loading entries and none for this mod. Character and system files received new timestamps, and the character container remained 595,260 bytes. This was an absence test for MHWAddSaveSlots; REFramework and unrelated installed mods remained present.

After the user closed Steam, the ordinary original directory was restored and **all 41 original hashes matched**. The seven mod Lua files were restored with mutations disabled, and the backup companion was stopped. The five-entry recovery snapshot, a separately verified export, the trimmed snapshots, and the subsequent mod-absent result were retained outside Git.

## Limits

- Live capacity testing reached five characters. Six through sixteen are covered only by generalized code and mocked allocation/copy checks.
- The persisted-index guard was observed as a runtime field and tested at mocked serialization boundaries. The new implementation was not separately booted without the mod while its file still had five entries; the live absence test used the deliberately trimmed result.
- The native three were present after trimming. The first was loaded and saved without the mod; the other two were not separately played after that final save, and their complete records were not compared field by field.
- Deliberate disk-full, interrupted-write, and every possible native save-flow failure were not injected in the live game. Synthetic checks and retained snapshots provide narrower evidence.
- Whole-snapshot recovery is available; merging older extras with newer native progress is not implemented.
- The creation-screen visual artifacts have not been diagnosed. Other game builds, multiplayer, Cloud use, and long-term progression are unvalidated.
