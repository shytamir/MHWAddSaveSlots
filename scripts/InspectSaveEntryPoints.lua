-- Development-only, one-shot metadata probe for an unarmed copied-save session.
-- Does not invoke save, import, export, serialization, or character methods.
-- Direct lookup includes methods that REFramework's get_methods() filters out.
local finished = false
local message = "Waiting for metadata capture"

local function describe(method)
    if not method then return {found=false} end
    local parameters = {}
    for _,td in ipairs(method:get_param_types()) do
        parameters[#parameters+1] = td:get_full_name()
    end
    return {found=true, name=method:get_name(), parameters=parameters,
        returns=method:get_return_type():get_full_name(), static=method:is_static(),
        address=tostring(method:get_function())}
end

local function capture()
    local session = json.load_file("MHWAddSaveSlots.session.json")
    assert(session and session.isolated==true and session.mutation_enabled==false,
        "Requires an isolated, unarmed copied-save session")
    local report = {version=1, utc=os.date("!%Y-%m-%dT%H:%M:%SZ"),
        scope="Direct method lookup and enum constants only; no game operation invoked", types={}}
    local candidates = {
        ["via.storage.saveService.SaveService"] = {
            "exportToMemory", "importFromMemory", "loadMetadataFromMemory", "releaseImportMemory",
            "exportToMemoryNative", "get_SaveState", "get_LastSaveResult"},
        ["via.storage.saveService.ExportToMemoryParam"] = {
            ".ctor", "get_TargetSlotTbl", "get_Metadata", "get_BufferReserveSize", "get_MemoryArray"},
        ["via.Serializer"] = {"serializeMessagePackInternal", "deserializeMessagePackInternal",
            "serializeJsonInternal", "deserializeJsonInternal"}
    }
    for name,names in pairs(candidates) do
        local td = sdk.find_type_definition(name)
        local entry = {found=td~=nil, methods={}}
        if td then
            for _,methodName in ipairs(names) do
                entry.methods[methodName] = describe(td:get_method(methodName))
            end
        end
        report.types[name] = entry
    end
    report.enums = {}
    for _,name in ipairs({"via.Serializer.Options", "via.storage.saveService.SaveState"}) do
        local td = sdk.find_type_definition(name)
        local values = {}
        if td then
            for _,field in ipairs(td:get_fields()) do
                if field:is_static() then
                    local ok,value = pcall(function() return field:get_data(nil) end)
                    values[field:get_name()] = ok and tostring(value) or ("error: "..tostring(value))
                end
            end
        end
        report.enums[name] = values
    end
    assert(json.dump_file("MHWAddSaveSlots.save-entry-points.json", report)~=false, "Report write failed")
    message = "Save entry-point metadata captured"
    log.info("MHWAddSaveSlots: "..message)
end

re.on_application_entry("UpdateBehavior", function()
    if finished then return end
    finished = true
    local ok,err = pcall(capture)
    if not ok then message=tostring(err); log.error("MHWAddSaveSlots metadata: "..message) end
end)
re.on_draw_ui(function()
    if imgui.tree_node("Wilds save entry-point investigation") then
        imgui.text(message)
        imgui.tree_pop()
    end
end)
