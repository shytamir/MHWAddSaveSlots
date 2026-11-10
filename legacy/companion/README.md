# Retained companion prototype

This directory holds the superseded external-companion backend for historical investigation and regression tests. Add Save Slots 1.0 uses the Lua archive and preservation modules under `reframework/autorun/`; it neither loads nor ships these files. Do not install this directory over the released mod.

- `MHWAddSaveSlots/compat.lua`: old companion-backed preservation hooks, used by `tests/test_safety.lua` alongside the current selector.
- `MHWAddSaveSlots/probe.lua`: old diagnostic UI module.
- `BackupStore.psm1`, `SaveCompanion.ps1`: prototype whole-file archive store and companion process.
- `Test-SaveCompanion.ps1`: retained synthetic backup/receipt/trim regression checks. Run from the repository root with `pwsh -NoProfile -File legacy/companion/Test-SaveCompanion.ps1`; fixtures remain under ignored `work/sandbox-fixtures/`.

The [historical companion guide](../../docs/history/legacy-companion.md) describes the former architecture. Its setup is not a current installation procedure. No runtime process or personal save is needed for the fixture test. Keep useful historical tests; the current runtime's language does not determine the language of developer tooling.
