# Post-release findings — 2026-11-10

Author-reported behavior after using the published mod with Steam Cloud enabled. These observations supplement [the copied-save package tests](lua-backend-validation.md); they are not measurements collected by the maintenance tools.

## Online play

The author added one fresh character in slot 4, rather than cloning an existing character. Attempts to go online from added slots failed. Slots 4–16 must therefore be described as offline-only in player instructions. Online play is confirmed only for the first three slots in an original, unmodified vanilla save with its original characters. Do not extend that confirmation to the native slots of an expanded save, clones, or recovered characters.

The author's explanation is that game systems use the save index to look up a registered hunter ID, and that the server-side registration cannot be replaced until the previous hunter is vacated through the native deletion flow. That mechanism and other possible server checks have not been independently traced here. Save-index spoofing is not part of this maintenance work. Steam Cloud file synchronization and in-game hunter registration are separate concerns; Cloud being enabled does not establish online compatibility or cross-device recovery coverage.

## Autosave stalls

With four entries, the author observed autosaves producing a freeze, a few intervening frames, and eventual recovery, with stalls sometimes lasting 4–5 seconds. They did not perform manual saves in that run. The defect is present with a single fresh extra character; it does not require sixteen entries or cloning.

Static source inspection identifies synchronous work in the save hooks:

1. Before the native save, `preservation.lua` serializes every character and calls `archive:capture`.
2. Capture validates all Base64 strings, computes byte-by-byte Lua checksums, writes the whole JSON snapshot, reads/parses it again, and verifies it before allowing native execution.
3. The native completion hook calls `archive:commit`, which reads, parses, and checksums that whole snapshot again before writing the small commit record.

This is a plausible source of multiple stalls, not a measured attribution of the reported 4–5 seconds to individual stages. The pinned REFramework [JSON binding](https://github.com/praydog/REFramework/blob/d052e8fd3fd41d0a1a33394fcf6e6c19be39b1ee/src/mods/bindings/Json.cpp) performs these file operations synchronously. Its [script runner](https://github.com/praydog/REFramework/blob/d052e8fd3fd41d0a1a33394fcf6e6c19be39b1ee/src/mods/ScriptRunner.cpp) holds a Lua execution mutex during callbacks; calling this work from another hook does not make it background work. The existing Wilds save-export prior art runs engine operations on the game logic callback; it does not supply an asynchronous complete-character backup implementation.

The agreed direction is to let the native save run without waiting for backup verification, process the new backup afterward in bounded batches across frames, and retain the last verified backup until the new one is verified. Do not defer the native save merely to check a backup. A process exit before backup completion must leave the previous verified archive available and must not cause startup to shrink a successfully expanded native save. Small persisted capacity information and unfinished work need explicit handling; a coroutine alone does not make a large native serializer or JSON call preemptible.

A [post-save candidate](autosave-backups.md) has now been implemented locally with regression coverage. Live timing validation remains outstanding and was postponed by the user. Do not describe the documentation-only 1.0.1 update as a performance fix or claim a frame-time budget has been achieved. The installed and published runtime remains unchanged.

## Trimming and removal

The author reported that the trim/removal procedure worked perfectly. No new failure was reported for that workflow.

## Documentation update

The 1.0.1 package updates player-facing online restrictions and discloses the autosave performance defect. Its eight runtime Lua files are unchanged from 1.0. No runtime fix, online workaround, tag, or Nexus publication is implied by preparing this package.
