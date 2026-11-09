-- Read-only diagnostics; automatic capture is limited to armed test sessions.
local control=require("MHWAddSaveSlots.control")
local prefix = "MHWAddSaveSlots"
local requested = false
local last_status = "Press Capture for a read-only snapshot"
local last_snapshot = 0
local extra_types = {}
local seen_gui = {}
local M = {}
local function safe(fn)
    local ok, value = pcall(fn)
    if ok then return value end
    return nil
end
local function name(t) return t and t:get_full_name() or "<nil>" end
local function inspect_type(t)
    local result = {name=name(t), fields={}, methods={}}
    result.parent = name(t:get_parent_type())
    for _, f in ipairs(t:get_fields()) do
        table.insert(result.fields, {name=f:get_name(), type=name(f:get_type()), static=f:is_static(),
            offset=f:get_offset_from_base(), literal=f:is_literal(),
            value=f:is_literal() and tostring(safe(function() return f:get_data(nil) end)) or nil})
    end
    for _, m in ipairs(t:get_methods()) do
        local params = {}
        local types, names = m:get_param_types(), m:get_param_names()
        for i, p in ipairs(types) do params[i] = {type=name(p), name=names[i]} end
        table.insert(result.methods, {name=m:get_name(), parameters=params,
            returns=name(m:get_return_type()), static=m:is_static(),
            address=tostring(m:get_function())})
    end
    return result
end
local function object_summary(obj)
    if not obj then return nil end
    local r = {type=name(obj:get_type_definition()), fields={}}
    local t = obj:get_type_definition()
    for depth=1,4 do
        if not t then break end
        for _, f in ipairs(t:get_fields()) do
            if not f:is_static() then
                local value = safe(function() return f:get_data(obj) end)
                local kind = type(value)
                if kind == "number" or kind == "boolean" then r.fields[f:get_name()] = value
                elseif kind == "userdata" then
                    r.fields[f:get_name()] = safe(function() return name(value:get_type_definition()) end) or "<native>"
                else r.fields[f:get_name()] = value == nil and "<nil>" or "<string>" end
            end
        end
        t = t:get_parent_type()
    end
    return r
end
local seeds = {
    "app.SaveDataManager", "ace.SaveDataManagerBase", "ace.SaveDataManagerBase.cRequest",
    "ace.SaveDataManagerBase.cSaveRequest", "app.savedata.cUserSaveData", "app.savedata.cUserSaveParam",
    "app.savedata.cBasicParam", "ace.cSaveDataMain", "ace.cSaveDataParam", "app.GUIManager",
    "app.GameFlowManager", "app.GUIID", "app.GAME_STATE", "System.Array", "via.UserData",
    "via.storage.saveService.SaveFile", "app.GUI010000", "app.GUI010001", "app.GUI010002",
    "app.cSaveDataHelper", "app.cGameJumper", "app.TitleState", "app.PlayingState",
    "ace.GameStateType", "app.GUIID.ID", "ace.cSaveDataBase",
    "app.SoundTitleController", "app.savedata.cSystemSaveData", "app.savedata.cSystemSaveParam",
}
local function snapshot()
    local report = {version=1, utc=os.date("!%Y-%m-%dT%H:%M:%SZ"), types={}, objects={}, gui=seen_gui}
    local visited = {}
    local function visit(t, parents)
        if not t or visited[name(t)] then return end
        visited[name(t)] = true
        report.types[name(t)] = inspect_type(t)
        if parents then visit(t:get_parent_type(), true) end
    end
    for _, s in ipairs(seeds) do visit(sdk.find_type_definition(s),true) end
    for s,_ in pairs(extra_types) do visit(sdk.find_type_definition(s),true) end
    for _, s in ipairs({"app.SaveDataManager", "app.GUIManager", "app.GameFlowManager"}) do
        report.objects[s] = object_summary(sdk.get_managed_singleton(s))
    end
    local flow = sdk.get_managed_singleton("app.GameFlowManager")
    local state = flow and flow:get_field("_CurrentGameState")
    if state then
        visit(state:get_type_definition(),true)
        report.current_state = object_summary(state)
        for _,f in ipairs(state:get_type_definition():get_fields()) do
            local v = safe(function() return f:get_data(state) end)
            if type(v)=="userdata" then
                local td = safe(function() return v:get_type_definition() end)
                if td then visit(td,true); report.objects[f:get_name()]=object_summary(v) end
            end
        end
    end
    local gui = sdk.get_managed_singleton("app.GUIManager")
    local all_gui = gui and gui:get_field("_AllGUI")
    report.gui_objects = {}
    if all_gui then
        for i=0,all_gui:get_size()-1 do
            local obj = all_gui:get_element(i)
            if obj then
                local td = obj:get_type_definition()
                visit(td,true)
                report.gui_objects[name(td)] = object_summary(obj)
                local context = safe(function() return obj:get_field("Context") end)
                local param = context and context:get_field("Param")
                if param then
                    visit(param:get_type_definition(),true)
                    report.objects[name(td)..".Param"] = object_summary(param)
                end
            end
        end
    end
    local commands = control.read("discovery-request")
    for _,s in ipairs(commands and commands.types or {}) do visit(sdk.find_type_definition(s),true) end
    local flow_manager = gui and gui:get_field("_FlowManager")
    local handles = flow_manager and flow_manager:call("getAllHandles")
    local function walk(obj,path,depth)
        if not obj or depth>4 then return end
        local t = safe(function() return obj:get_type_definition() end)
        if not t or t:is_value_type() or t:is_array() or name(t)=="System.String" then return end
        visit(t,true)
        report.objects[path]=object_summary(obj)
        for _,f in ipairs(t:get_fields()) do
            if not f:is_static() then
                local ft=name(f:get_type())
                if ft:find("Flow") or ft:find("Context") or ft:find("StateMachine") or ft:find("Title") then
                    walk(safe(function() return f:get_data(obj) end),path.."."..f:get_name(),depth+1)
                end
            end
        end
    end
    if handles then
        for i=0,handles:get_size()-1 do walk(handles:get_element(i),"flow_handle_"..i,0) end
    end
    local manager = sdk.get_managed_singleton("app.SaveDataManager")
    local data = manager and manager:get_field("_UserSaveData")
    local slots = data and data:get_field("_Data")
    if slots then
        report.slot_count = slots:get_size()
        report.slots = {}
        for i=0,slots:get_size()-1 do
            local slot = slots:get_element(i)
            report.slots[i+1] = {index=i, present=slot~=nil,
                active=slot and slot:get_field("Active") or nil}
            local basic=slot and slot:get_field("_BasicData")
            if basic then
                report.slots[i+1].hunter=basic:get_field("CharName")
                report.slots[i+1].palico=basic:get_field("OtomoName")
            end
        end
        report.current_index=manager:get_field("CurrentUserDataIndex")
    end
    json.dump_file(prefix .. ".discovery.json", report)
    last_status = "Read-only snapshot written; slots: " .. tostring(report.slot_count)
end
function M.update()
    if requested or os.clock()-last_snapshot>10 then
        if not sdk.get_managed_singleton("app.SaveDataManager") then return end
        last_snapshot = os.clock()
        if not requested and not control.enabled(control.read("session")) then return end
        requested = false
        local ok, err = pcall(snapshot)
        if not ok then last_status=tostring(err); log.error(prefix .. ": " .. last_status) end
    end
end
function M.draw()
    if imgui.tree_node("Wilds fourth character (experimental)") then
        imgui.text("This diagnostics panel is read-only")
        imgui.text(last_status)
        if imgui.button("Capture save and loader APIs") then requested=true end
        imgui.tree_pop()
    end
end
return M
