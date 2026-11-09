# MHWAddSaveSlots

Experimental REFramework proof of concept for a **fourth Monster Hunter Wilds character**, selected through its own overlay.

**Proven on an isolated save copy:** create an independent clone named Gupta with Palico Kirikau, enter gameplay, save, exit the game, restart, recover the fourth record from disk, and load it back into the Grand Hub. The original three entries remain present. This is a research prototype, not a production-ready slot expansion.

The prototype adds a record to the existing `data001Slot.bin`. It does not create a separate fourth character file, alter the three-row menu assets, or swap characters between native slots. Directory substitution below is only the test harness protecting the user's originals.

## Tested environment

Tested locally on 2026-11-09:

| Component | Version |
| --- | --- |
| Game | Windows Steam edition, `1.042.00.03` |
| Steam build ID | `25921695` |
| REFramework | `v1.5.9.1+514`, built 2026-10-11 |
| REFramework revision | `d052e8fd3fd41d0a1a33394fcf6e6c19be39b1ee` |

Other versions have not been validated. The installed environment contained other mods; compatibility with a clean installation or other mod combinations has not been established. Hooks resolve managed methods by name, which does not guarantee compatibility with future builds.

## Requirements

- Existing working REFramework installation; its DLL is not included or replaced.
- Steam Cloud disabled for Wilds and Steam restarted in **Offline Mode**. Friends' offline status is insufficient. Recheck Offline Mode after restarting Steam.
- A verified backup and an isolated copy of the whole Wilds Steam userdata directory.
- PowerShell for isolation/recovery, with permission to rename the relevant userdata directories.

**Use copied saves only.** The clone retains the source's hunter/online identifiers. Multiplayer, Cloud synchronization, achievements, account services, and unique identity generation are outside this experiment.

## Installation

With Wilds closed, copy both the entry script and the entire module folder into the game's matching paths:

```text
reframework/autorun/MHWAddSaveSlots.lua
reframework/autorun/MHWAddSaveSlots/
    control.lua
    compat.lua
    poc.lua
    probe.lua
```

Leave existing REFramework files and other mods in place. Without an explicitly armed isolated session, operations are read-only. REFramework's **Script Generated UI** contains discovery and selector panels; Insert toggles its input interface.

Runtime JSON files belong in `reframework/data` and must not be committed. They can contain character names, account-related data, and diagnostic addresses.

## Prepare an isolated test

Disable Cloud for Wilds, restart Steam in Offline Mode, then fully exit both Wilds and Steam before preparing the copy. Closing Steam's window does not exit its process.

Run from the repository, replacing the example paths. `AppDirectory` is the whole `Steam/userdata/<account>/2246340` folder, not `remote` or `win64_save`.

```powershell
.\scripts\SaveSandbox.ps1 -Action Prepare `
  -SessionDirectory 'D:\save-tests\session-001' `
  -AppDirectory 'C:\Program Files (x86)\Steam\userdata\ACCOUNT\2246340' `
  -GameDirectory 'C:\Program Files (x86)\Steam\steamapps\common\MonsterHunterWilds' `
  -CloudDisabled -SteamOffline

.\scripts\SaveSandbox.ps1 -Action Arm `
  -SessionDirectory 'D:\save-tests\session-001'
```

Prepare copies and hashes every file, preserves the original as `2246340.mhw4-original-<id>`, and places the verified copy at the normal app path. It writes `session.json` and `original-sha256.json` outside Git. The two switches confirm settings already established in Steam; they do not configure Steam.

Prepare defaults to mutations disabled. Arm verifies the retained originals again and enables this session for 12 hours. Keep the session armed throughout creation, saving, and every restart using its four-character files. Renew with Arm before expiry if needed. Do not disarm, remove the mod, or allow the lease to expire while using expanded saves: vanilla paths can truncate the fourth record or crash when reading the saved selection. Restore the originals before ordinary play.

## Create and select the fourth character

1. Start Steam, verify it is still in Offline Mode, and launch Wilds with the isolated copy active.
2. At the title screen, open **Start Game / Select Saved Data**. The native menu still has three visible rows.
3. Use **Create Gupta + Kirikau as character 4** in the mod's overlay. If needed, press Insert to enable mouse interaction with REFramework.
4. Use **Load Gupta + Kirikau (character 4)**. The mod completes the native selection flow using index 3.
5. Enter offline gameplay, save normally, and use **Save and Quit**. Confirm the additional save prompt and wait until the game closes.
6. Keep the same armed session and `MHWAddSaveSlots.native.json`, restart Wilds, reopen Select Saved Data, and use the mod's Load button again. No clone operation should run during this restart.

Creation currently copies occupied slot 1 and assigns the fixed names above. It does not implement the new-character editor, fresh progression, arbitrary source selection, deletion, or a fifth slot. Before attachment, creation audits the source and clone for shared mutable managed objects; this traversal may briefly stall the game.

`MHWAddSaveSlots.native.json` records expected capacity and the isolated session ID. It contains no character data; the character remains in the native save container. An empty fourth allocation is not proof of recovery, and the selector refuses to load an inactive fourth entry.

## Recovery and removal

After testing, fully exit Wilds and Steam, then run:

```powershell
.\scripts\SaveSandbox.ps1 -Action Restore `
  -SessionDirectory 'D:\save-tests\session-001'
```

Restore retains the experimental app directory as `2246340.mhw4-result-<id>`, restores the preserved original directory, checks every original file against its SHA-256 manifest, and disables mutation mode. Keep Cloud disabled until restoration succeeds. The retained result includes Gupta's experimental save; it is not imported into the originals.

For an interrupted session:

```powershell
.\scripts\SaveSandbox.ps1 -Action Status `
  -SessionDirectory 'D:\save-tests\session-001'
```

Inspect the exact paths in the journal. Restore supports interruption between directory renames and is idempotent after successful restoration. If the script cannot run, with both processes closed, preserve the current `active` directory elsewhere, rename `original` back to `active`, and verify against `original-sha256.json` before reopening Steam. Never overwrite the preserved original with experimental files or resolve a Cloud conflict over it without checking the copies.

Only after restoring ordinary three-character saves, remove the entry script and its same-named module folder to uninstall. The diagnostic `MHWAddSaveSlots.*.json` files can then be archived or removed. Keep the journal and manifest with retained test data. Leave the existing REFramework DLL and other mods alone.

## Implementation and evidence

`poc.lua` queues UI actions for `UpdateBehavior`; it does not mutate saves in drawing callbacks. It uses `cUserSaveParam.create` and `copyFrom`, expands `cUserSaveData._Data`, verifies the current-save accessor at index 3, and drives `GUI010102.selectFinish` through its list selection. Compatibility changes run on the game's own save/load calls.

Static inspection of the tested executable found that `cUserSaveData.create` allocates three entries and `copyFrom` copies the shorter array length, returning false when lengths differ. The prototype expands a three-entry copy destination when its source contains four. It also expands the main destination before `SaveDataManager.systemRequestUserLoad` when the armed session's capacity metadata says four. No raw offset patches or hooks borrowed from RE4 are used.

Observed in game:

- The clone audit visited 76,760 mutable objects on each side with zero shared objects.
- The custom selector created and loaded Gupta/Kirikau into the Grand Hub at current index 3.
- Expanding only the live array was insufficient: save staging dropped the fourth entry, and the next launch crashed when title code used remembered index 3.
- Expanding the save-copy destination grew the test `data001Slot.bin` from 595,260 to 858,988 bytes. Startup still required the load-destination fix; growth alone was not treated as persistence proof.
- With both fixes, a fresh process read four active records from disk, including Gupta/Kirikau and all three preceding entries. The creation-command file was empty. The custom selector then returned Gupta/Kirikau to the Grand Hub in `app.IngameState`, current index 3.

These checks establish the fourth-character proof of concept on this build. They do not establish long-term progression reliability, exhaustive integrity of every field in the expanded test container, other native menu operations, online safety, or compatibility without the mod. Original files are protected independently by directory preservation and hash verification.

A subsequent [test with this mod absent](docs/native-compatibility-test.md) successfully booted and saved through a native character after selecting that character normally. The save shrank from 858,988 to 595,260 bytes, exactly the earlier three-character size. This strongly indicates that the extra record was discarded. A safe startup selection therefore does not establish preservation of extra characters without the mod; expanded native storage must not be their only recoverable copy.

## Development checks

```powershell
.\scripts\Test-SaveSandbox.ps1
git diff --check
```

The synthetic sandbox test covers verified copying, default-disabled mutations, explicit arming, retaining modified test data, restoring original hashes, refusing to re-arm a restored session, and repeated restoration. It does not simulate the game or prove Lua hook behavior. Live results are described separately above.

`probe.lua` captures read-only type metadata and runtime summaries on request, or every ten seconds while a test session is armed. The standalone selector is hidden outside isolated sessions. Developer command and reload JSON files are restricted to fixed actions/modules and the matching session; a command already present at Lua startup is not replayed. Saves, runtime dumps, journals, and binaries belong outside Git. Do not commit or push without a user request.

## Possible next direction

A separate mod-managed character library remains a possible follow-up. This experiment establishes that Wilds can play a fourth managed record and persist it with targeted compatibility hooks. Separate storage would additionally need a verified serializer, crash-safe writes, load/save routing, identity handling, and recovery behavior. That architecture is not implemented here.

## References

- [REFramework Lua SDK](https://refdocs.praydog.com/api/sdk.html)
- [Installed revision's managed-array implementation](https://github.com/praydog/REFramework/blob/d052e8fd3fd41d0a1a33394fcf6e6c19be39b1ee/shared/sdk/SystemArray.cpp)
- [Wilds save schema and parser](https://github.com/kvasszn/ree-save-editor/tree/3de477f22352fcdd2a88751e794844947f3ebae9)

Apache-2.0; see `LICENSE`. Game files, personal saves, and third-party mods are not included.
