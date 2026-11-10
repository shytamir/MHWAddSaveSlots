# Wilds Expanded Characters

Additional Monster Hunter Wilds characters in the native save container, selected through a REFramework overlay. Supports independent clones, fresh characters, native-range persisted selection, character snapshots, recovery into an extra entry, and explicit trimming to three entries.

**Version 0.3.0-dev.3 — development candidate.** The packaged Lua-only mod passed copied-save tests for clone and fresh characters, saving and restarting, trimming, a mod-absent native save, and archive recovery followed by Save and Quit and another restart. `dev.3` updates documentation and package metadata; its Lua files are identical to the tested `dev.2` package. This is not a stable release. Use a separate copy of ordinary three-character saves. Do not upgrade an expanded save from the companion prototype with this package. The earlier `dev.1` package uses the raw reconstruction path that failed live loading.

**Known limitation:** the recovery/load/save test reset the first three characters' recent/favourite menu arrays. Every other serialized byte in those three records matched the pre-recovery snapshot. The exact reset boundary remains unclassified; preserve snapshots and expect to reconfigure those menus. This limitation is accepted for continued experimental testing.

## Requirements

- Windows Steam Monster Hunter Wilds. The tested building blocks used game `1.042.00.03`, Steam build `25921695`.
- An existing REFramework installation. Tested revision: `d052e8fd3fd41d0a1a33394fcf6e6c19be39b1ee` (`v1.5.9.1+514`). The DLL is not bundled.
- Steam Cloud disabled for Wilds, Steam Offline Mode, and a separate preserved backup of the entire Wilds userdata directory.
- Free disk space for retained character archives. This candidate retains all snapshots and can consume substantial space.

Players do not run PowerShell, a companion script, or an additional DLL. Developer isolation and regression tools remain in the repository.

## Install on a copied save

1. Close Wilds and fully exit Steam. Preserve the entire `Steam/userdata/ACCOUNT/2246340` directory separately before substituting a copy. Keep the originals untouched throughout testing.
2. Extract the ZIP's `reframework` folder into the Wilds installation, beside `MonsterHunterWilds.exe`. Preserve unrelated REFramework files and mods. Do not copy developer probes or old runtime JSON into a new installation.
3. Start Steam in Offline Mode, then Wilds. Open **Start Game / Select Saved Data** and press **Insert**.
4. Under **Script Generated UI → Wilds expanded characters**, choose **Set up this copied save**, then confirm that the originals are preserved and this is the copy.
5. Wait for **Local backups ready**. Setup captures and verifies the initial characters. If setup reports an error, keep the save copy and its backup folder for inspection.

Without activation, operations remain read-only. The two setup buttons do not copy Steam userdata or verify Steam settings; those preparation steps remain the user's responsibility.

## Add and play characters

- **Clone:** choose a source and names, then **Add independent clone**. The mod checks for shared mutable objects before attachment. Clones retain the source's online identifiers; this candidate is for offline testing.
- **Fresh character:** choose **Add empty entry for a fresh character**, then **Create new in…**. Complete the game's normal editor and tutorial.
- Use the overlay's **Load** buttons for extra entries. Keep REFramework open while clicking; the controls are disabled when it is closed to reduce click-through.
- Save normally, wait for the save to complete and **backup verified**, then fully restart and load that entry again.

The native first three entries remain in place. The implementation limit is sixteen entries; gameplay has been demonstrated through five with this Lua-only package. Sixteen is not a measured engine limit.

## Backups and recovery

Keep this entire directory, including activation and every library:

```text
MonsterHunterWilds/reframework/data/MHWAddSaveSlots/
```

The mod uses Wilds' MessagePack serializer to capture every allocated character before a native character-save write. It verifies the files by reading them back, then publishes an immutable snapshot. A separate commit records successful native-save completion. A captured snapshot without a commit is retained and labelled as unconfirmed.

A failed backup refuses the native character write. Missing or damaged backup data keeps character saving blocked while allowing native inspection. Do not remove backup data to clear an error. Exit the game and restore the complete backup folder, or return to the separately preserved original save directory.

To recover an archived character, open Select Saved Data and expand **Recover an archived character**. Choose a snapshot and its character number, then **Restore into an extra entry**. This uses an empty extra entry or appends one; it does not replace any of the current first three. Load the recovered entry and save normally. Verify it after a full restart before treating the recovery as successful.

These are character snapshots, not whole Steam userdata backups. They do not restore all system settings or every file in the save directory. Recovery through the package's archive UI into an extra slot passed gameplay, native Save and Quit, full restart, and reload after trimming and a mod-absent save. See the menu-array limitation above. Do not edit archive files, mix library directories, or share personal snapshots publicly.

## Trim and remove

1. Keep the complete backup folder. Load one of the native first three characters.
2. Choose **Prepare trim: save and back up all characters**. Wait for **Trim: ready**.
3. Choose **Confirm trim to three characters**, then wait for **Trim: complete** and the native save to finish.
4. Close Wilds. Preserve the complete backup folder, remove only `reframework/autorun/MHWAddSaveSlots.lua` and its `MHWAddSaveSlots` module directory, then test the trimmed copy without the mod.

Trimming retains expanded archives. Removing the mod while the native save is still expanded can allow a later native save to discard extra entries. Keep the recovery snapshots and the independent original-directory backup.

After testing, close Wilds and fully exit Steam. Preserve the experimental userdata directory elsewhere, restore the untouched original directory, and verify its files against the original backup. Do not accept a Steam Cloud conflict over the originals.

## Evidence and development

See [validation and remaining release gates](docs/lua-backend-validation.md) and [the save-byte investigation](docs/save-byte-investigation.md). The earlier companion implementation and its tests remain in the source repository; it is not a player dependency or part of this ZIP.

Focused developer checks:

```text
lua tests/test_archive.lua
lua tests/test_preservation.lua
lua tests/test_snapshot_codec.lua
lua tests/test_safety.lua
powershell -File scripts/Build-Package.ps1
```

Fengari is also supported for the Lua checks. The repository retains `SaveSandbox.ps1`, `Test-SaveSandbox.ps1`, and the prior companion tests. Live testing must use isolated copies. The build script includes only an explicit source/document allowlist and verifies the bytes inside the ZIP.

Apache-2.0; see `LICENSE`. No game files, personal saves, runtime settings, third-party mods, or binaries are distributed.
