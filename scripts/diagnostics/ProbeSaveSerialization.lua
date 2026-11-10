-- Development-only byte extraction on an isolated, unarmed save copy.
-- Runs once on UpdateBehavior. Reads the first existing character; never assigns
-- records, requests a save, imports data, or changes the persisted selection.
-- Output is engine object serialization, NOT a native encrypted save container.
local finished = false
local message = "Waiting for serialization probe"
local report = {version=1, scope="Read-only engine serialization of copied character data"}
local function checkpoint(stage)
    report.stage = stage
    json.dump_file("MHWAddSaveSlots.serialization-probe.json", report)
end

local function run()
    local session = json.load_file("MHWAddSaveSlots.session.json")
    assert(session and session.isolated==true and session.mutation_enabled==false,
        "Requires an isolated, unarmed copied-save session")
    report.utc = os.date("!%Y-%m-%dT%H:%M:%SZ")
    checkpoint("checking related service types")
    report.related_services = {}
    local types = sdk.find_type_definition("System.Object"):get_types_inheriting_from_this()
    for _,td in ipairs(types) do
        local name = td:get_full_name()
        if name:find("SaveService",1,true) then
            local methods = {}
            for _,methodName in ipairs({"exportToMemory", "importFromMemory",
                "loadMetadataFromMemory", "releaseImportMemory", "exportToMemoryNative"}) do
                local method = td:get_method(methodName)
                if method then
                    local params = {}
                    for _,p in ipairs(method:get_param_types()) do params[#params+1]=p:get_full_name() end
                    methods[methodName] = {parameters=params, returns=method:get_return_type():get_full_name(),
                        static=method:is_static(), address=tostring(method:get_function())}
                end
            end
            report.related_services[name] = methods
        end
    end
    checkpoint("checking serializer contract")
    local manager = assert(sdk.get_managed_singleton("app.SaveDataManager"), "Save manager missing")
    assert(not manager:call("get_IsSaveRunning") and not manager:call("get_IsSaveLoadFlowRunning"),
        "Wait until the save selection screen is idle")
    local root = assert(manager:get_field("_UserSaveData"), "User save data missing")
    local records = assert(root:get_field("_Data"), "Character array missing")
    assert(records:get_size()>=3, "Expected the copied character array")
    local record = assert(records:get_element(0), "First character missing")
    local td = record:get_type_definition()
    assert(td:get_full_name()=="app.savedata.cUserSaveParam", "Unexpected character type")
    local serializer = assert(sdk.find_type_definition("via.Serializer"))
    local serialize = assert(serializer:get_method("serializeMessagePackInternal"))
    local convert = assert(sdk.find_type_definition("System.Convert"))
    local base64 = assert(convert:get_method("ToBase64String(System.Byte[])"), "Base64 overload missing")
    local options = sdk.find_type_definition("via.Serializer.Options"):get_field("None"):get_data(nil)
    assert(options==0, "Unexpected serializer default")
    report.source_type = td:get_full_name()
    report.character_count = records:get_size()
    checkpoint("serializing first copied character")
    local bytes = assert(serialize:call(nil, td:get_runtime_type(), record, options), "Serializer returned nil")
    bytes:add_ref()
    assert(bytes:get_type_definition():get_full_name()=="System.Byte[]", "Unexpected serializer return type")
    report.byte_count = bytes:get_size()
    assert(report.byte_count>0 and report.byte_count<=64*1024*1024, "Unexpected serialized length")
    checkpoint("encoding returned byte array")
    local encoded = base64:call(nil, bytes)
    assert(type(encoded)=="string" and #encoded==4*math.ceil(report.byte_count/3), "Invalid base64 result")
    local output = "MHWAddSaveSlots.character-messagepack."..os.date("!%Y%m%dT%H%M%SZ")..".json"
    local existing = io.open(output,"rb")
    if existing then existing:close(); error("Output already exists") end
    assert(json.dump_file(output, {format="engine-object-messagepack", source_type=report.source_type,
        byte_count=report.byte_count, base64=encoded})~=false, "Snapshot write failed")
    report.output = output
    checkpoint("complete")
    message = "Captured "..report.byte_count.." bytes from the copied character"
end

re.on_application_entry("UpdateBehavior", function()
    if finished then return end
    finished = true
    local ok,err = pcall(run)
    if not ok then
        report.failed_at = report.stage
        report.error = tostring(err)
        checkpoint("failed")
        message = tostring(err)
        log.error("MHWAddSaveSlots serialization probe: "..message)
    else log.info("MHWAddSaveSlots serialization probe: "..message) end
end)
re.on_draw_ui(function()
    if imgui.tree_node("Wilds serialization investigation") then
        imgui.text(message)
        imgui.tree_pop()
    end
end)
