# Autosave backup maintenance — 1.0.2 candidate

## Status and scope

Local implementation and synthetic regression checks only. The user postponed runtime validation and prohibited computer control for this task. No game or Steam controls were automated, no save directory was substituted, and no installed mod files were changed. The existing 1.0 and documentation-only 1.0.1 archives are retained unchanged. This candidate has not been published.

The author authorized committing and pushing this candidate to main, with publication held until copied-save runtime validation is complete. Source availability on main is not a release or evidence that the observed stalls have been resolved in game.

The verified local package is `work/autosave-candidate-1.0.2/AddSaveSlots-1.0.2.zip`, SHA-256 `2d1c743a7e689046b1e60d19c8925fa310bcdc6dab4fcda49f246a50b04ba43f`. Its twelve-entry allowlist contains the player README, license, nine Lua files, and manifest. All packaged source/document hashes passed verification. Syntax checks covered 24 Lua files, and 33 relative documentation links resolved.

The reported symptom was autosave freezing/stuttering up to 4–5 seconds with four entries, including a fresh fourth character. Actual stage timings have not been measured in Wilds. The game's native save interval is not an established disk-I/O benchmark; compiled engine code, asynchronous service work, and this mod's Lua processing must not be conflated.

## Changes and rationale

- Native character-save hooks no longer serialize all characters, write a full backup, or verify a full backup before allowing the save. They retain the native index/capacity guards and write small capacity/receipt records. A failure to record required capacity information still refuses an unsafe native write; it is not a wait for backup verification.
- Successful native completion queues the request's target for capture on `UpdateBehavior`. The engine serializer and Base64 conversion run in separate update calls. Large-string validation, checksumming, file writes, and read-back comparison use checkpoints.
- The archive still uses the v1 JSON snapshot/publication/commit format. Streaming writes preserve that format and compare exact bytes read back in chunks of at most 16 KiB. No extra runtime library or DLL is required; file access uses REFramework's existing restricted `io.open`.
- The ordinary background path computes character checksums once. Exact streaming read-back replaces a full JSON parse and checksum pass, and commit reuses the just-verified metadata instead of rereading the whole file again. Existing archived snapshots still receive full validation when loaded. Title-menu setup/recovery and explicit trim confirmation retain their synchronous verification paths.
- A single worker and at most one newer pending capture bound the queue. Before all character data has been copied into immutable Lua strings, a superseding save or reuse of the staging object cancels the capture. Once frozen, it finishes even if another save arrives; repeated autosaves must not starve already-captured backups. An older completion never acknowledges a newer save or overwrites its latest receipt.
- Snapshot publication occurs only after read-back succeeds. Failed, cancelled, or interrupted files remain unpublished and cannot replace the previous verified snapshot. A background error warns without preventing subsequent native saves; a later successful backup clears the warning.

The scheduler's **2 ms target and eight-step cap are cooperative limits, not a hard frame-time guarantee**. Checksums yield every 4 KiB; validation and I/O use 16 KiB chunks. Individual native serializer/Base64 calls, disk calls, and garbage collection cannot be preempted. Runtime counters record per-stage work and the largest observed worker update; they are available under `stats.backup` in the private runtime report. These counters have not yet been collected from a live candidate run.

## Interrupted saves and capacity

Backup completion can lag behind native save completion. Startup therefore cannot infer native capacity solely from the latest verified character archive.

Small immutable `native-<id>.json` records retain the attempted capacity, the previous capacity, purpose, revision, and checksum. A separate completion marker follows native success. An uncompleted attempt conservatively reserves the larger capacity, including the previous native capacity even if no corresponding character backup finished. A completed native trim can restart at three entries while the retained expanded archive remains available.

Revisions are reserved before a snapshot job yields. A newer native save therefore outranks an older background snapshot that completes later. Capacity records are verified on startup; malformed or corrupt records do not silently reset capacity to three. These records describe capacity, not a recoverable character backup, and do not replace independent whole-directory backups.

After a crash or early exit, the native file may contain newer progress than the last verified archive. Captures are post-save character snapshots, potentially taken across multiple updates, not an atomic byte copy of the native container. Exact correspondence to the completed native file is not claimed. A restart can reserve the native slot count without inventing an archive of that newer progress.

Before downgrading to 1.0/1.0.1, finish a verified backup and close Wilds. Older versions understand the character archives but ignore the separate native-capacity records. Trimming still requires explicit preparation and a verified expanded archive.

## Automated evidence

The candidate passes 187 Lua assertions across six suites. New coverage includes:

- Native execution and completion occur before any character encoding; serialization/commit failures in the worker do not prevent later native saves.
- Previous verified backups survive write failure, corrupt read-back, close failure, cancellation, and incomplete publication; open file handles are closed on failure/cancellation.
- Streaming files parse as valid JSON, preserve Unicode/escaped names and exact character bytes, retain v1 load compatibility, and keep each read/write request at or below 16 KiB.
- Streaming capture/commit does not parse its full snapshot again. Known checksum vectors still match across chunk boundaries.
- CPU-budget checkpoints, maximum-step limits with a constant clock, separate native-call updates, cancellation cleanup, and queued cancellation are exercised.
- Pending and partially captured work can be superseded. Frozen work can finish across another native save without acknowledging it, publishing conflicting revisions, or reducing its newer capacity.
- Restart before backup completion retains expanded native capacity. An incomplete trim reserves the previous expanded capacity; a completed trim restarts at three while retaining expanded archives. Corrupt capacity metadata/completion markers are rejected.

These tests use synthetic saves and mocked engine objects. They do not prove that a native staging object is immutable between callbacks on every save path, characterize engine serialization or Lua GC pauses, or demonstrate improved in-game frame times. Existing PowerShell fixture tests remain available and unchanged.

## Deferred copied-save validation

When the user resumes runtime testing, preserve/hash/journal a verified copy under the repository's isolation protocol, then have the user operate Steam and Wilds:

1. Confirm the baseline game and REFramework versions and capture the old path's stage timings if practical; do not infer stage costs from the reported total stall.
2. Exercise autosaves with four entries and a fresh fourth character. Confirm native saves finish while backup status progresses; inspect serializer, Base64, checksum, I/O and maximum worker-update measurements alongside observed frame behavior.
3. Verify successful native save/restart/reload both after a completed backup and after an exit while a backup is unfinished. Confirm all native characters and the extra character remain accessible and the previous verified archive remains recoverable.
4. Exercise repeated saves during backup processing, archive recovery, five-entry capacity, trim to three, and mod-absent native loading on the trimmed copy. Check the known recent/favourite-menu limitation separately.
5. Restore and hash-verify the originals. Record live observations and remaining limitations before treating this as a release-ready fix.

If measurements identify a dominant uninterruptible engine call, investigate its existing APIs/prior art before choosing another implementation. Do not add a companion or native DLL merely because the cooperative path has not yet been measured.
