# Save-byte access investigation

Investigation started 2026-11-10. Target: Wilds `1.042.00.03`, Steam build `25921695`, REFramework revision `d052e8fd3fd41d0a1a33394fcf6e6c19be39b1ee`.

## Question and scope

Can Lua obtain Wilds' serialized save content through the game's existing APIs, using REFramework for reflection, calls, hooks, and file output?

Backup output under `reframework/data` is already available and is not being probed again. No external backup process is intended for players. Existing PowerShell tests and copied-save preparation tools remain useful development tools. Prior companion protocols and safeguards are prototypes, not architectural constraints.

No native DLL is justified yet. If a specific missing operation is established, first check existing extensions before considering a small helper. Do not reproduce REFramework functionality.

## Prior art inspected

| Project | What the inspected source does | Relevance and limits |
| --- | --- | --- |
| [Wilds Save Import and Export](https://github.com/paean-of-guidance/mhws-save-import-export/tree/5ed449660e867d4561ed37e41d2cff2a4519be72) | Reads `app.SaveDataManager.getUserSaveData(index)`, traverses the selected character's fields, exports JSON, and imports chosen portions. Uses REFramework JSON output without EgLib; mutations run on the game logic thread. | Direct Wilds precedent for Lua character export. This is reconstructed character data, not a read of the serialized save container. Shared visited objects are skipped and some values have custom conversions. Complete recovery would need its own validation. MIT licensed. |
| [EgLib filesystem service](https://github.com/eigeen/ref-eglib/blob/650d2ec79473bfc2d34ef5b8726fd63a57fe2018/src/module/fs.rs) | Provides user-authorized external text-file access. Its `read_text_file` uses Rust `read_to_string`; file access permissions expire when the script reloads. | Used optionally by the Wilds exporter. The inspected interface does not establish binary save reads. External destination access is unnecessary for our backup output. No dependency has been added. |
| [REE Save Editor](https://github.com/kvasszn/ree-save-editor/tree/3de477f22352fcdd2a88751e794844947f3ebae9) | Standalone editor with its own container/cryptography implementation and embedded Lua scripting. | Its `SaveFile.read_native_fields` is an editor binding, not a Wilds method callable through REFramework. Useful format research, not proof of an in-game byte API. No source incorporated. |
| [DRAP save-slot module](https://github.com/ArsonAssassin/DRAP/blob/770a11485a4e23c29d4b949c42e68c089a5f1641/source/autorun/DRAP/SaveSlot.lua) | Uses `via.storage.saveService.SaveService` through REFramework in Dead Rising Deluxe Remaster to change a save mount. | Provides a concrete engine type name to inspect in Wilds. It does not demonstrate byte extraction, and another game's API behavior must not be assumed. No path redirection is proposed for this probe. |
| [Tether DD2 serializer](https://github.com/Precyse/Tether/blob/3328c5dc012209d6be32b67d11285544b10c8425/adapters/dd2/src/serializer.cpp) | Invokes `via.Serializer` JSON methods with a runtime `System.Type`, an object or JSON string, and options. | Establishes a calling-contract lead for engine object serialization. This is another game and does not prove native save-container export in Wilds. |

These are source-inspection findings, not local runtime validation of those projects.

## Static evidence

- Static disassembly of this build's `cSaveRequest.execMainFunction` shows a call into an engine service after preparing the target and metadata. That establishes a lower-level path to investigate, not an accessible byte buffer or a supported Lua signature.
- REFramework's pinned source exposes reflected method calls, native-singleton calls, and managed-memory access. Its Lua object `deserialize_native` facility is not evidence of a matching save-container export operation.
- [REFramework's method enumeration](https://github.com/praydog/REFramework/blob/d052e8fd3fd41d0a1a33394fcf6e6c19be39b1ee/src/mods/bindings/Sdk.cpp) filters methods with null function pointers or stub code. Direct `get_method(name)` lookup must therefore be checked before treating an omitted method as absent.
- [REE Save Editor's Wilds research](https://github.com/kvasszn/ree-save-editor/blob/3de477f22352fcdd2a88751e794844947f3ebae9/rev/wilds.genny) records an `ExportToMemoryParam` layout and export/import save-service states. This supports a targeted investigation, not reuse of its offsets or proof that those operations work in this build.
- This installed executable contains the names `exportToMemory`, `importFromMemory`, `loadMetadataFromMemory`, and `releaseImportMemory`. Names in the binary alone do not establish callable implementations.
- The captured `via.Serializer.serializeMessagePackInternal` address resolves to a nontrivial function in the installed executable. Runtime tests below establish its character-object serialization behavior; complete save recovery is a separate test.

## Runtime metadata evidence

The user ran two read-only captures on a verified copy of the original three-character saves. Mutation remained disabled. These probes inspected reflected types and methods; they did not invoke game save, export, import, or serialization operations.

- `via.storage.saveService.SaveService` exists and exposes 88 methods through filtered enumeration. These include `addDataClass`, `saveSingle`, `loadSingle`, and state/configuration accessors. That list does not expose a save-byte getter or export operation. The encryption-key getter is not a save-byte source.
- `InspectSaveTypes.lua` scanned 194,343 types derived from `System.Object` and selected 161 storage, serialization, and stream-related types.
- `via.storage.saveService.ExportToMemoryParam` exposes `TargetSlotTbl` (`Int32[]`), `Metadata` (`Object`), `BufferReserveSize` (`UInt64`), and **`MemoryArray` (`Byte[]`)** properties. The import and metadata-load parameter types also exist. Their existence does not show whether the service entry points are implemented.
- `via.Serializer` exposes static MessagePack serialization returning `Byte[]`, and MessagePack deserialization returning `Object`, plus JSON equivalents. This is a separate object-serialization candidate; it must not be described as a native encrypted save-container dump.

- `InspectSaveEntryPoints.lua` directly looked up `exportToMemory`, `importFromMemory`, `loadMetadataFromMemory`, `releaseImportMemory`, and `exportToMemoryNative` on the save-service type: none were found. A subsequent search of types whose names contain `SaveService` found no additional entry points with those names. This is a reflection-access limitation for the inspected names, not proof that the underlying engine lacks the operations.
- The runtime constants are `via.Serializer.Options.None = 0` and `FloatValueCompression = 1`.

## Runtime byte extraction and detached round trip

The user ran the developer probes at Select Saved Data on the isolated three-character copy. All game calls ran on `UpdateBehavior`. No character was assigned, no selection was changed, and neither probe requested a save. No companion was running.

`ProbeSaveSerialization.lua` obtained the first existing `app.savedata.cUserSaveParam` from `_UserSaveData._Data`. The working engine call is:

```lua
local runtimeType = record:get_type_definition():get_runtime_type()
local serializer = sdk.find_type_definition("via.Serializer")
local bytes = serializer:get_method("serializeMessagePackInternal")
    :call(nil, runtimeType, record, 0)
-- Keep returned managed objects referenced while using them.
bytes:add_ref()
```

This returned **3,876,896 bytes**. The diagnostic snapshot contains those bytes encoded with the game's `System.Convert.ToBase64String` and written through REFramework JSON output. Base64 is a diagnostic transport choice, not a proposed player-facing backup format. Writing files under `reframework/data` was already available.

`ProbeSaveRoundTrip.lua` then established:

| Check | Observed result |
| --- | --- |
| Repeat serialization of the copied source | Matches the captured snapshot exactly |
| `deserializeMessagePackInternal(runtimeType, bytes, None)` | Returns a distinct `app.savedata.cUserSaveParam` root object |
| Serialize the detached reconstructed object | 3,876,896 bytes, byte-for-byte identical to the source serialization |
| Serialize the live source before and after that reconstruction | Identical |
| Decode the snapshot read from disk in small chunks, then re-encode | All 3,876,896 bytes reproduced exactly |

The first disk decode attempt raised `caught (...) exception` while passing the entire multi-megabyte Base64 string through `FromBase64String`; a three-byte sample decoded successfully. The exact cause within argument conversion or decoding was not established. Using 4,096-character chunks with the existing `System.Convert.FromBase64String`, `sdk.create_managed_array("System.Byte", length)`, and `System.Array.Copy` operations succeeded. No custom decoder, memory offsets, DLL, or external process was needed.

The detached reconstruction used the freshly serialized engine byte array. The separate disk-read check proved that the saved snapshot reconstructs identical bytes. The reconstructed character was **not attached or loaded into gameplay**. Root-object separation does not constitute a full mutable-object sharing audit.

## Conclusion and remaining validation

**Lua can obtain and round-trip serialized character data through Wilds' own APIs. A native DLL is not justified for this demonstrated route.** This supports evaluating an in-process character backup design while retaining expanded native records for gameplay; it does not require choosing external save swapping or changing storage architecture now.

These bytes are the engine's MessagePack representation of one character object, **not the complete encrypted `data001Slot.bin`**, and they do not include the entire system-save container. A native whole-file byte export remains unproven. Byte-identical reserialization also cannot detect fields that the serializer omits on both passes.

Before replacing the companion implementation, test restoring an archived character into a copied native container, loading it in gameplay, saving, restarting, and checking progression and appearance. Also validate fresh characters, every expanded entry, shared/native data coverage, and preservation through trim and mod-absent saves. Backup timing, interrupted writes, and startup behavior still need a design and validation appropriate to the chosen representation. Existing prototype protocols are not requirements for that design.

## Cleanup and checks

The user closed Wilds and Steam after testing. `SaveSandbox.ps1 -Action Restore` retained the test directory, restored the original directory, verified all **41 original files**, and disabled the isolation/mutation marker. The temporary entry-point autorun probe was removed after its capture. Runtime dumps, snapshots, hashes, and session journals remain private and outside Git.

The four developer Lua probes passed syntax checks with the existing Fengari runner. `git diff --check` passed. These checks are separate from the live results above. The production mod and existing PowerShell tests were not changed; no production regression suite was rerun for these developer probes.

## Status

Investigation complete for a Lua-only character serialization route. The detached tests above did not validate gameplay recovery. A subsequent copied-save live test on 2026-11-10 found that raw deserialization crashed on load; native factory/init/copy plus preservation of two omitted menu arrays passed load, save, restart, and reload. The corrected route and its remaining integration gates are recorded in [the backend validation report](lua-backend-validation.md). Whole native-container export remains unvalidated. No new DLL or external runtime dependency is required by the demonstrated character-recovery route.
