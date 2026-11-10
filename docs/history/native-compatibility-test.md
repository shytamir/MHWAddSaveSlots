# Expanded save with MHWAddSaveSlots absent

Historical prototype test. For the released mod's trimming and recovery evidence, see [the integrated validation report](../lua-backend-validation.md).

Test date: 2026-11-09. Game `1.042.00.03`, Steam build `25921695`, REFramework revision `d052e8fd3fd41d0a1a33394fcf6e6c19be39b1ee`. Prototype source: commit `3b1cc0c`.

With a native character selected and saved normally, Wilds booted, displayed its three native characters, and loaded and saved the first character with MHWAddSaveSlots absent. That save operation reduced the character container from **858,988 to 595,260 bytes**, exactly its earlier three-character size. The working conclusion is that the fourth character was discarded by the normal save path.

This was an absence test for **this mod**. REFramework and the user's other existing mods remained installed. It was not a clean, unmodified-game compatibility test.

## Procedure

1. Preserve the ordinary save directory intact, record SHA-256 hashes, and install a verified copy of the retained four-character experimental saves. Steam Cloud was disabled and Steam Offline Mode was used.
2. With MHWAddSaveSlots enabled, select the first native character using the ordinary menu, enter gameplay, and use Save and Quit. The user performed the game interaction.
3. Preserve and hash the prepared save directory. The final runtime snapshot contained four active records, including Gupta/Kirikau, and current index 0. The character container was 858,988 bytes after saving. The persisted selection was prepared through normal game behavior; it was not independently decoded.
4. With Wilds closed, move the loader and all four supporting Lua files out of `autorun`, verify their hashes, and disable the mutation marker.
5. Launch manually without MHWAddSaveSlots, check the ordinary character menu, load the first native character, and Save and Quit.
6. Preserve and hash the resulting save directory and log. Restore the ordinary originals and verify all 41 files against their original hashes. Restore the five mod Lua files with mutations disabled.

## Evidence

| Observation | Evidence |
| --- | --- |
| Four active characters before the absence test | Runtime snapshot from preparation; Gupta/Kirikau present, current index 0 |
| Mod absent for the test run | Its five Lua files were outside autorun; the run's REFramework script-loading log did not list its loader |
| Game booted and the native three appeared | User observation |
| Mod selector was absent | User observation |
| First native character loaded and saved normally | User observation; character and system save files received new timestamps |
| Character container shrank | Filesystem measurement: 858,988 bytes before, 595,260 bytes afterward |
| Result matches prior three-character size | Comparison with earlier preserved baseline |
| Ordinary originals restored | All 41 files matched their recorded SHA-256 hashes |

The fourth record's loss is a strong inference from the size returning exactly to the earlier three-character container size. No record-by-record decode or further in-game reload of the resulting save was performed. The other two native characters were observed in the menu before the save; their complete post-save records were not independently compared.

## Design consequence

A native-range startup selection allows this tested path to boot without MHWAddSaveSlots. It does not provide evidence that vanilla save processing preserves extra records. Native-file-only storage is therefore unsuitable as the sole recoverable copy of extra characters.

A future design needs independent, verified recovery data and a recovery procedure that preserves changes made to the native three while the mod was absent. Restoring an older whole-file backup blindly could undo that newer progress. A three-character compatibility export should archive the extra characters before conversion.

No storage redesign, automatic recovery, trimming feature, or capacity increase was implemented as part of this test. Personal saves, account identifiers, runtime dumps, and session journals remain outside Git.
