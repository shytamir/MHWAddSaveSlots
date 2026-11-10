# Add Save Slots

> **WARNING: THIS MOD CAN DAMAGE OR DESTROY YOUR SAVE DATA. USE IT ENTIRELY AT YOUR OWN RISK.**
>
> Using this mod may cause corruption, overwritten or unreadable saves, lost characters, or permanent loss of progress. **The author accepts no responsibility or liability for damage to save data, lost progress, or any other loss resulting from installing, using, updating, or removing this mod, to the fullest extent permitted by applicable law.** The mod is provided **AS IS**, without warranty or any guarantee that damaged or lost data can be recovered.
>
> **Make a separate backup of your entire save directory before installation and keep it outside the game and mod directories.** Do not rely solely on this mod's own backups. You are responsible for preserving your backups and recovering your data. Do not use the mod if you are unwilling to accept the risk of losing your save data.

Additional Monster Hunter Wilds characters in the native save container, selected through a REFramework overlay. Supports independent clones, fresh characters, native-range persisted selection, character snapshots, recovery into an extra entry, and explicit trimming to three entries.

**Version 0.3.0.** First setup requires a save with the normal three native slots. Do not upgrade an expanded save from the older companion-based version with this package.

**Known limitation:** recovery can reset the native characters' recent/favourite menus. You may need to reconfigure those menus afterward.

## Requirements

- Monster Hunter Wilds for Windows on Steam.
- An existing REFramework installation. The REFramework DLL is not bundled.
- A separate preserved backup of the entire Wilds userdata directory.
- Free disk space for retained character archives. The mod retains all snapshots and can consume substantial space.

Players do not run PowerShell, a companion script, or an additional DLL.

## Installation

1. Close Wilds and make a separate backup of the entire `Steam/userdata/ACCOUNT/2246340` directory.
2. Extract the ZIP's `reframework` folder into the Wilds installation, beside `MonsterHunterWilds.exe`. Preserve unrelated REFramework files and mods.
3. Start Steam, then Wilds. Open **Start Game / Select Saved Data** and press **Insert**.
4. Under **Script Generated UI → Add Save Slots**, choose **Set up Add Save Slots**, then **Confirm backup and enable** once your separate backup is ready.
5. Wait for **Local backups ready**. Setup captures and verifies the initial characters. If setup reports an error, keep the save and its backup folder for inspection.

Without activation, operations remain read-only. The two setup buttons do not copy Steam userdata; preserve the whole-directory backup separately before setup.

## Add and play characters

- **Clone:** choose a source and names, then **Add independent clone**. The mod checks for shared mutable objects before attachment. Clones retain the source's online identifiers.
- **Fresh character:** choose **Add empty entry for a fresh character**, then **Create new in…**. Complete the game's normal editor and tutorial.
- Use the overlay's **Load** buttons for extra entries. Keep REFramework open while clicking; the controls are disabled when it is closed to reduce click-through.
- Save normally, wait for the save to complete and **backup verified**, then fully restart and load that entry again.

The native first three entries remain in place. The selector's capacity is sixteen entries.

## Backups and recovery

Keep this entire directory, including activation and every library:

```text
MonsterHunterWilds/reframework/data/MHWAddSaveSlots/
```

The mod uses Wilds' MessagePack serializer to capture every allocated character before a native character-save write. It verifies the files by reading them back, then publishes an immutable snapshot. A separate commit records successful native-save completion. A captured snapshot without a commit is retained and labelled as unconfirmed.

A failed backup refuses the native character write. Missing or damaged backup data keeps character saving blocked while allowing native inspection. Do not remove backup data to clear an error. Exit the game and restore the complete backup folder, or return to the separately preserved original save directory.

To recover an archived character, open Select Saved Data and expand **Recover an archived character**. Choose a snapshot and its character number, then **Restore into an extra entry**. This uses an empty extra entry or appends one; it does not replace any of the current first three. Load the recovered entry and save normally. Verify it after a full restart before treating the recovery as successful.

These are character snapshots, not whole Steam userdata backups. They do not restore all system settings or every file in the save directory. See the menu-reset limitation above. Do not edit archive files, mix library directories, or share personal snapshots publicly.

## Trim and remove

1. Keep the complete backup folder. Load one of the native first three characters.
2. Choose **Prepare trim: save and back up all characters**. Wait for **Trim: ready**.
3. Choose **Confirm trim to three characters**, then wait for **Trim: complete** and the native save to finish.
4. Close Wilds. Preserve the complete backup folder, remove only `reframework/autorun/MHWAddSaveSlots.lua` and its `MHWAddSaveSlots` module directory, then launch the game and verify the three native characters.

Trimming retains expanded archives. Removing the mod while the native save is still expanded can allow a later native save to discard extra entries. Keep the recovery snapshots and the independent original-directory backup.

To restore the whole-directory backup, close Wilds and fully exit Steam. Preserve the current userdata directory elsewhere, restore your separate backup to its original location, and verify its files before relaunching.

Apache-2.0; see `LICENSE`. No game files, personal saves, runtime settings, third-party mods, or binaries are distributed.
