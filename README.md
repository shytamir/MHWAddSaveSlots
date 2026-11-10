# Add Save Slots

> **WARNING: THIS MOD CAN DAMAGE OR DESTROY YOUR SAVE DATA. USE IT ENTIRELY AT YOUR OWN RISK.**
>
> Using this mod may cause corruption, overwritten or unreadable saves, lost characters, or permanent loss of progress. **The author accepts no responsibility or liability for damage to save data, lost progress, or any other loss resulting from installing, using, updating, or removing this mod, to the fullest extent permitted by applicable law.** The mod is provided **AS IS**, without warranty or any guarantee that damaged or lost data can be recovered.
>
> **Make a separate backup of your entire save directory before installation and keep it outside the game and mod directories.** Do not rely solely on this mod's own backups. You are responsible for preserving your backups and recovering your data. Do not use the mod if you are unwilling to accept the risk of losing your save data.

Add more characters to Monster Hunter Wilds and select them through the **Add Save Slots** REFramework panel. Create a fresh hunter, clone an existing character, recover a character from a backup, or return your save to the original three slots.

**Version 1.0.2.** First setup requires a save with the game's normal three character slots.

**Slots 4 and above are for offline play only.** Added characters cannot currently go online. This applies to both fresh characters and clones.

**Online play is confirmed only for the first three slots in an original, unmodified vanilla save, with its original characters.** This confirmation does not extend to the first three slots in a mod-expanded save or to cloned or recovered characters. Steam Cloud synchronization is separate from in-game online play; enabling Cloud does not enable online play for added slots.

**Known limitation:** recovery can reset the native characters' recent/favourite menus. You may need to reconfigure those menus afterward.

**Performance limitation:** backup work runs incrementally after saving, but individual engine serialization and disk operations cannot be interrupted by the mod. Save-time pauses may still occur.

## Requirements

- Monster Hunter Wilds for Windows on Steam.
- An existing REFramework installation. The REFramework DLL is not bundled.
- A separate preserved backup of the entire Wilds userdata directory.
- Free disk space for retained character archives. The mod retains all snapshots and can consume substantial space.

## Installation

1. Close Wilds and make a separate backup of the entire `Steam/userdata/ACCOUNT/2246340` directory.
2. Extract the ZIP's `reframework` folder into the Wilds installation, beside `MonsterHunterWilds.exe`. Preserve unrelated REFramework files and mods.
3. Start Steam, then Wilds. Open **Start Game / Select Saved Data** and press **Insert**.
4. Under **Script Generated UI → Add Save Slots**, choose **Set up Add Save Slots**, then **Confirm backup and enable** once your separate backup is ready.
5. Wait for **Local backups ready**. Setup captures and verifies the initial characters. If setup reports an error, keep the save and its backup folder for inspection.

The mod stays inactive until you complete setup. Setup does not replace the separate whole-directory backup in step 1.

## Add and play characters

- **Clone:** choose a source character and new hunter/Palico names, then **Add independent clone**. Clones retain the source's online identifiers.
- **Fresh character:** choose **Add empty entry for a fresh character**, then **Create new in…**. Complete the game's normal editor and tutorial.
- Use the panel's **Load** buttons for extra characters. Press **Insert** to open REFramework before clicking the controls.
- Save normally, wait for the save to complete and **backup verified**, then fully restart and load that entry again.

The first three characters remain available through the game's normal menu. The Add Save Slots panel supports up to sixteen entries; entries 4–16 are for offline play only.

## Backups and recovery

Keep this entire backup directory:

```text
MonsterHunterWilds/reframework/data/MHWAddSaveSlots/
```

Native saves proceed without waiting for character backup verification. After a successful save, the mod captures the characters, then writes and verifies the new backup over multiple frames. The previous verified backup remains intact until the new backup is complete. Snapshots preserve character state captured after saving; they are not copies of the native save files.

Wait for **backup verified** when you need an up-to-date recovery point. If you exit before a backup finishes, the previous verified backup remains available, but the newest progress may exist only in the game's save files. An unfinished backup is never promoted to a verified recovery point.

If background backup writing or verification fails, the panel shows a warning and native saves continue. Keep the existing backup folder and your separate whole-directory backup; do not delete backup data to clear a warning. A later successful backup can clear a temporary backup failure. Save-safety errors concerning missing or damaged slot information are separate and may still prevent unsafe operations.

To recover a character, open **Select Saved Data → Add Save Slots → Recover an archived character**. Choose a snapshot and its character number, then **Restore into an extra entry**. This fills an empty extra slot or adds one; it does not replace any of the current first three characters. Load the recovered character, save normally, and verify it after restarting the game.

Character backups do not restore every game setting or file in the Steam save directory. Keep your separate whole-directory backup too. Recovery may reset recent/favourite menus as described above. Do not edit backup files, mix their directories, or share personal backups publicly.

## Trim and remove

1. Keep the complete backup folder. Load one of the native first three characters.
2. Choose **Prepare trim: save and back up all characters**. Wait for **Trim: ready**.
3. Choose **Confirm trim to three characters**, then wait for **Trim: complete** and the native save to finish.
4. Close Wilds. Preserve the complete backup folder, remove only `reframework/autorun/MHWAddSaveSlots.lua` and its `MHWAddSaveSlots` module directory, then launch the game and verify the three native characters.

Returning to three slots retains the backups of your extra characters. Removing the mod before completing this procedure can allow a later game save to discard extra characters. Keep both the mod's backups and your separate whole-directory backup.

Before reverting to an older Add Save Slots version, wait for **backup verified**, then close Wilds. Older versions do not understand the separate slot information used while a new backup is unfinished.

To restore the whole-directory backup, close Wilds and fully exit Steam. Preserve the current userdata directory elsewhere, restore your separate backup to its original location, and verify its files before relaunching.

Apache-2.0; see `LICENSE`. No game files, personal saves, runtime settings, third-party mods, or binaries are distributed.
