# Developer diagnostics

These manual investigation scripts are excluded from the player package. They were written against the game and REFramework versions recorded in [the validation report](../../docs/lua-backend-validation.md). Inspect their guards, callback behavior, and current engine metadata before running them. Do not automatically copy this folder into autorun or run every script as a test suite.

| Script | Purpose |
| --- | --- |
| `InspectSaveTypes.lua`, `InspectSaveEntryPoints.lua` | Enumerate engine metadata in an isolated, unarmed copied-save session. |
| `ProbeSaveSerialization.lua` | Serialize a copied character into diagnostic output without attaching or saving a character. |
| `ProbeSaveRoundTrip.lua` | Reconstruct detached records and compare bytes using the serialization capture. |
| `ProbeRestoreInitialization.lua` | Investigate detached record initialization using an armed copied-save session and private restore request, without attaching or saving the record. |
| `ObservePackageTest.lua` | Read-only observation of an already prepared copied-save package test. |
| `TestSnapshotRestore.lua` | Mutation harness for an explicitly armed copied-save session and private restore request. It can replace a copied native slot and intercept save callbacks; it is not the player recovery UI. |

Follow [the repository save-safety rules](../../AGENTS.md). Capture outputs and private requests under ignored/local storage, never in Git. Prefer the packaged recovery UI for product validation; use these harnesses only for a specific investigation. Historical findings are in [the API investigation](../../docs/save-byte-investigation.md).
