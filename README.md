# Add Save Slots

> **WARNING: THIS MOD CAN DAMAGE OR DESTROY YOUR SAVE DATA. USE IT ENTIRELY AT YOUR OWN RISK.**
>
> Using this mod may cause corruption, overwritten or unreadable saves, lost characters, or permanent loss of progress. **The author accepts no responsibility or liability for damage to save data, lost progress, or any other loss resulting from installing, using, updating, or removing this mod, to the fullest extent permitted by applicable law.** The mod is provided **AS IS**, without warranty or any guarantee that damaged or lost data can be recovered.
>
> **Make a separate backup of your entire save directory before installation and keep it outside the game and mod directories.** Do not rely solely on this mod's own backups. You are responsible for preserving your backups and recovering your data. Do not use the mod if you are unwilling to accept the risk of losing your save data.

Add more characters to Monster Hunter Wilds and select them through the **Add Save Slots** REFramework panel. Create a fresh hunter, clone an existing character, recover a character from a backup, or return your save to the original three slots.

**Version 1.0.** First setup requires a save with the game's normal three character slots.

**Known limitation:** recovery can reset the native characters' recent/favourite menus. You may need to reconfigure those menus afterward.

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

The first three characters remain available through the game's normal menu. The Add Save Slots panel supports up to sixteen entries.

## Backups and recovery

Keep this entire backup directory:

```text
MonsterHunterWilds/reframework/data/MHWAddSaveSlots/
```

The mod backs up your characters before saving and verifies the stored backup. A backup is marked as complete after the game reports a successful save. Backups from interrupted or unfinished saves are retained and labelled as unconfirmed.

If a backup cannot be verified, the mod blocks character saving. Do not delete backup data to clear an error. Exit the game and restore the complete backup folder, or restore your separate whole-directory save backup.

To recover a character, open **Select Saved Data → Add Save Slots → Recover an archived character**. Choose a snapshot and its character number, then **Restore into an extra entry**. This fills an empty extra slot or adds one; it does not replace any of the current first three characters. Load the recovered character, save normally, and verify it after restarting the game.

Character backups do not restore every game setting or file in the Steam save directory. Keep your separate whole-directory backup too. Recovery may reset recent/favourite menus as described above. Do not edit backup files, mix their directories, or share personal backups publicly.

## Trim and remove

1. Keep the complete backup folder. Load one of the native first three characters.
2. Choose **Prepare trim: save and back up all characters**. Wait for **Trim: ready**.
3. Choose **Confirm trim to three characters**, then wait for **Trim: complete** and the native save to finish.
4. Close Wilds. Preserve the complete backup folder, remove only `reframework/autorun/MHWAddSaveSlots.lua` and its `MHWAddSaveSlots` module directory, then launch the game and verify the three native characters.

Returning to three slots retains the backups of your extra characters. Removing the mod before completing this procedure can allow a later game save to discard extra characters. Keep both the mod's backups and your separate whole-directory backup.

To restore the whole-directory backup, close Wilds and fully exit Steam. Preserve the current userdata directory elsewhere, restore your separate backup to its original location, and verify its files before relaunching.

Apache-2.0; see `LICENSE`. No game files, personal saves, runtime settings, third-party mods, or binaries are distributed.
