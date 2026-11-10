-- Development-only detached round trip. Run after ProbeSaveSerialization.lua.
-- Never attaches the reconstructed object to the game or requests a save.
local finished = false
local message = "Waiting for detached round trip"
local report = {version=1, scope="Detached engine object round trip; no record assignment or save request"}
local function checkpoint(stage)
    report.stage = stage
    json.dump_file("MHWAddSaveSlots.roundtrip-probe.json", report)
end
local function run()
    local session = json.load_file("MHWAddSaveSlots.session.json")
    assert(session and session.isolated==true and session.mutation_enabled==false,
        "Requires an isolated, unarmed copied-save session")
    report.utc = os.date("!%Y-%m-%dT%H:%M:%SZ")
    local previous = assert(json.load_file("MHWAddSaveSlots.serialization-probe.json"))
    assert(previous.stage=="complete" and type(previous.output)=="string")
    assert(previous.output:match("^MHWAddSaveSlots%.character%-messagepack%.%d+T%d+Z%.json$"),
        "Unexpected snapshot filename")
    local snapshot = assert(json.load_file(previous.output))
    assert(snapshot.format=="engine-object-messagepack" and snapshot.source_type=="app.savedata.cUserSaveParam")
    assert(type(snapshot.base64)=="string" and type(snapshot.byte_count)=="number" and
        snapshot.byte_count>0 and snapshot.byte_count<=64*1024*1024 and
        #snapshot.base64==4*math.ceil(snapshot.byte_count/3), "Invalid snapshot")
    local manager = assert(sdk.get_managed_singleton("app.SaveDataManager"))
    assert(not manager:call("get_IsSaveRunning") and not manager:call("get_IsSaveLoadFlowRunning"),
        "Wait until save selection is idle")
    local live = assert(manager:get_field("_UserSaveData"):get_field("_Data"):get_element(0))
    local td = live:get_type_definition()
    assert(td:get_full_name()==snapshot.source_type)
    local serializer = assert(sdk.find_type_definition("via.Serializer"))
    local serialize = assert(serializer:get_method("serializeMessagePackInternal"))
    local deserialize = assert(serializer:get_method("deserializeMessagePackInternal"))
    local convert = assert(sdk.find_type_definition("System.Convert"))
    local encode = assert(convert:get_method("ToBase64String(System.Byte[])"))
    local decode = assert(convert:get_method("FromBase64String(System.String)"))
    local options = sdk.find_type_definition("via.Serializer.Options"):get_field("None"):get_data(nil)
    assert(options==0)
    local runtimeType = assert(td:get_runtime_type())
    local function serialized(value)
        local bytes = assert(serialize:call(nil, runtimeType, value, options))
        bytes:add_ref()
        local encoded = encode:call(nil, bytes)
        assert(type(encoded)=="string", "Encoding failed")
        return encoded, bytes:get_size(), bytes
    end
    checkpoint("serializing live record before detached round trip")
    local before,beforeCount,memoryBytes = serialized(live)
    report.snapshot_matches_current_record = before==snapshot.base64
    -- Test engine reconstruction independently of passing a multi-megabyte Lua
    -- string into the engine. That single-string decode failed in the first run.
    report.roundtrip_source = "fresh engine byte array"
    checkpoint("deserializing engine bytes to a detached object")
    local detached = assert(deserialize:call(nil, runtimeType, memoryBytes, options), "Deserializer returned nil")
    detached:add_ref()
    assert(detached:get_type_definition():get_full_name()==snapshot.source_type, "Unexpected restored type")
    assert(detached:get_address()~=live:get_address(), "Deserializer returned the live record")
    report.distinct_root_object = true
    checkpoint("serializing detached object")
    local roundtrip,count = serialized(detached)
    report.original_bytes = beforeCount
    report.roundtrip_bytes = count
    report.bytes_identical = roundtrip==before
    checkpoint("checking live record unchanged")
    local after = serialized(live)
    report.live_record_serialization_unchanged = before==after
    -- Rebuild the bytes read from disk using the game's decoder and array-copy
    -- operations. Each string argument is small; no raw array layout is assumed.
    checkpoint("checking chunked snapshot decoder")
    local arrayType = assert(sdk.find_type_definition("System.Array"))
    local copy = assert(arrayType:get_method(
        "Copy(System.Array, System.Int32, System.Array, System.Int32, System.Int32)"),
        "Five-argument array copy overload missing")
    local diskBytes = assert(sdk.create_managed_array("System.Byte", snapshot.byte_count))
    diskBytes:add_ref()
    local offset = 0
    checkpoint("decoding snapshot in small chunks")
    for first=1,#snapshot.base64,4096 do
        local part = assert(decode:call(nil, snapshot.base64:sub(first,first+4095)), "Chunk decoding failed")
        part:add_ref()
        local count = part:get_size()
        assert(offset+count<=snapshot.byte_count, "Decoded chunk exceeds expected length")
        copy:call(nil,part,0,diskBytes,offset,count)
        offset = offset+count
    end
    report.decoded_bytes = offset
    assert(offset==snapshot.byte_count, "Decoded size mismatch")
    checkpoint("verifying bytes reconstructed from disk snapshot")
    report.disk_snapshot_bytes_identical = encode:call(nil,diskBytes)==snapshot.base64
    assert(report.disk_snapshot_bytes_identical, "Decoded snapshot bytes differ")
    checkpoint("complete")
    message = "Detached round trip complete; identical bytes: "..tostring(report.bytes_identical)
end
re.on_application_entry("UpdateBehavior", function()
    if finished then return end
    finished = true
    local ok,err = pcall(run)
    if not ok then
        report.failed_at = report.stage
        report.error=tostring(err)
        checkpoint("failed")
        message=tostring(err)
        log.error("MHWAddSaveSlots round-trip probe: "..message)
    else log.info("MHWAddSaveSlots round-trip probe: "..message) end
end)
re.on_draw_ui(function()
    if imgui.tree_node("Wilds detached round-trip investigation") then
        imgui.text(message)
        imgui.tree_pop()
    end
end)
