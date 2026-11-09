local M = {}
local control=require("MHWAddSaveSlots.control")
-- A request left on disk from an earlier Lua runtime is never replayed.
if not _G.MHWAddSaveSlots_commands then
    _G.MHWAddSaveSlots_commands={}
    local stale=control.read("command")
    if stale.session_id and stale.id then _G.MHWAddSaveSlots_commands[stale.session_id..":"..stale.id]=true end
end
_G.MHWAddSaveSlots_commands = _G.MHWAddSaveSlots_commands or {}
local processed = _G.MHWAddSaveSlots_commands
local pending, last_request, last_poll = nil, nil, 0
local message = "Isolated test prototype"
local view = {title=false, isolated=false, slots=0, current=-1, enabled=false}
local position_window=true
_G.MHWAddSaveSlots_font=_G.MHWAddSaveSlots_font or imgui.load_font(nil,28)
local function context()
    local manager = sdk.get_managed_singleton("app.SaveDataManager")
    local flow = sdk.get_managed_singleton("app.GameFlowManager")
    local state = flow and flow:get_field("_CurrentGameState")
    local root = manager and manager:get_field("_UserSaveData")
    return manager, root, root and root:get_field("_Data"), state
end
local function guard()
    local session=control.read("session")
    assert(control.enabled(session), "Mutation is disabled or expired; arm an isolated test session")
    assert(_G.MHWAddSaveSlots_compat_registered and _G.MHWAddSaveSlots_load_registered,
        "Save/load compatibility hooks are unavailable")
    local manager,root,slots,state=context()
    assert(state and state:get_type_definition():get_full_name()=="app.TitleState", "Return to the title screen")
    assert(not manager:call("get_IsSaveRunning"), "Save operation in progress")
    assert(not manager:call("get_IsSaveLoadFlowRunning"), "Save/load flow in progress")
    return manager,root,slots
end
local function address(obj) return tostring(obj:get_address()) end
local function audit_graph(root, original_addresses)
    local seen, stack, count = {}, {root}, 0
    local function push(obj)
        if type(obj)~="userdata" then return end
        local ok,t=pcall(function() return obj:get_type_definition() end)
        if not ok or not t or t:is_value_type() or t:get_full_name()=="System.String" then return end
        stack[#stack+1]=obj
    end
    while #stack>0 do
        local obj=table.remove(stack)
        local key=address(obj)
        if not seen[key] then
            assert(not original_addresses or not original_addresses[key], "Clone shares a mutable object with its source: "..obj:get_type_definition():get_full_name())
            seen[key]=true; count=count+1
            assert(count<=500000,"Object graph exceeds audit limit")
            local t=obj:get_type_definition()
            if t:is_array() then
                for i=0,obj:get_size()-1 do push(obj:get_element(i)) end
            else
                while t do
                    for _,f in ipairs(t:get_fields()) do
                        if not f:is_static() then push(f:get_data(obj)) end
                    end
                    t=t:get_parent_type()
                end
            end
        end
    end
    return seen,count
end
local function create_copy(attach)
    local manager,root,slots=guard()
    assert(slots and slots:get_size()==3,"Expected exactly three source slots")
    local source=slots:get_element(0)
    assert(source and source:get_field("Active")~=0,"Source slot 1 is empty")
    local td=sdk.find_type_definition("app.savedata.cUserSaveParam")
    local clone=assert(td:get_method("create"):call(nil),"Character factory returned nil")
    clone:add_ref()
    assert(clone:call("copyFrom(ace.cSaveDataBase)",source)==true,"Game rejected the character copy")
    local original,n=audit_graph(source)
    local _,m=audit_graph(clone,original)
    local basic=clone:get_field("_BasicData")
    basic:set_field("CharName",sdk.create_managed_string("Gupta"))
    basic:set_field("OtomoName",sdk.create_managed_string("Kirikau"))
    local report={source_objects=n,clone_objects=m,shared_mutable_objects=0,attached=attach}
    if attach then
        local expanded=assert(sdk.create_managed_array("app.savedata.cUserSaveParam",4))
        expanded:add_ref()
        for i=0,2 do expanded[i]=slots:get_element(i) end
        expanded[3]=clone
        assert(expanded:get_element(3)==clone,"Array assignment failed")
        local previous=manager:get_field("CurrentUserDataIndex")
        local ok,err=pcall(function()
            root:set_field("_Data",expanded)
            assert(root:get_field("_Data"):get_size()==4,"Array attachment failed")
            manager:set_field("CurrentUserDataIndex",3)
            report.index3_resolves=manager:call("getCurrentUserSaveData")==clone
            assert(report.index3_resolves,"Current-save accessor rejected index 3")
            -- This is capacity metadata for this isolated session, not a save.
            local session=control.read("session")
            assert(json.dump_file("MHWAddSaveSlots.native.json",{session_id=session.session_id,slots=4})~=false,
                "Could not record startup capacity")
        end)
        manager:set_field("CurrentUserDataIndex",previous)
        if not ok then root:set_field("_Data",slots); error(err) end
    end
    json.dump_file("MHWAddSaveSlots.clone-test.json",report)
    message=attach and "Fourth record attached and accessor checked" or "Unattached clone has independent mutable data"
end
local function load_fourth()
    local manager,root,slots=guard()
    assert(slots and slots:get_size()==4,"A fourth character must exist first")
    local fourth=slots:get_element(3)
    assert(fourth and fourth:get_field("Active")~=0,"Fourth entry is empty; loading is refused")
    local guis=sdk.get_managed_singleton("app.GUIManager"):get_field("_AllGUI")
    local selector=nil
    for i=0,guis:get_size()-1 do
        local g=guis:get_element(i)
        if g and g:get_type_definition():get_full_name()=="app.GUI010102" then selector=g; break end
    end
    assert(selector and selector:get_field("_BaseState")==2,"Open Start Game / Select Saved Data first")
    local list=assert(selector:get_field("_DataList"),"Character selector has no list")
    -- The native controller reads this selection result when it closes. Its
    -- backing list accepts four entries; no replacement UI asset is required.
    list:call("set_ItemCount",4)
    list:call("set_SelectedIndex",3)
    assert(list:call("get_SelectedIndex")==3,"Native list rejected selection index 3")
    manager:set_field("CurrentUserDataIndex",3)
    assert(manager:call("getCurrentUserSaveData")==slots:get_element(3),"Fourth record is not current")
    selector:call("selectFinish")
    message="Requested Gupta through the native selection completion flow"
end
local actions={probe_copy=function() create_copy(false) end, append_clone=function() create_copy(true) end,
    load_fourth=load_fourth,
    save_fourth=function()
        assert(control.enabled(control.read("session")),"Isolated test session is not armed")
        local manager,root,slots,state=context()
        assert(state and state:get_type_definition():get_full_name()=="app.IngameState","Enter gameplay first")
        assert(slots:get_size()==4 and manager:get_field("CurrentUserDataIndex")==3,"Fourth character is not active")
        assert(not manager:call("get_IsSaveRunning") and not manager:call("get_IsSaveLoadFlowRunning"),"Save flow is busy")
        -- The inspected implementation explicitly permits a null callback.
        manager:call("requestSaveDataManualSave",nil)
        message="Requested a normal manual save; completion must be checked separately"
    end}
function M.update()
    if os.clock()-last_poll>1 then
        last_poll=os.clock()
        local session=control.read("session")
        local manager,root,slots,state=context()
        view.title=state and state:get_type_definition():get_full_name()=="app.TitleState"
        view.isolated=session.isolated==true
        view.slots=slots and slots:get_size() or 0
        view.current=manager and manager:get_field("CurrentUserDataIndex") or -1
        view.enabled=control.enabled(session)
        local req=control.read("command")
        if req and session and req.session_id==session.session_id and req.id and not processed[req.session_id..":"..req.id] then
            processed[req.session_id..":"..req.id]=true
            last_request=req.id
            pending=req.action
        end
    end
    if pending then
        local action=pending; pending=nil
        local ok,err=pcall(function() assert(actions[action],"Unknown action")() end)
        if not ok then message=tostring(err) end
        json.dump_file("MHWAddSaveSlots.result.json",{action=action,ok=ok,message=message,id=last_request})
    end
end
function M.draw()
    if imgui.tree_node("Fourth character selector") then
        imgui.text(message)
        imgui.text("Offline test copy only. Clone retains source online identity.")
        if imgui.button("Check an independent copy of character 1") then pending="probe_copy" end
        if imgui.button("Create Gupta and Kirikau as character 4") then pending="append_clone" end
        if imgui.button("Load Gupta (fourth character)") then pending="load_fourth" end
        imgui.tree_pop()
    end
end
function M.window()
    if not view.title or not view.isolated then return end
    if position_window then
        imgui.set_next_window_pos({70,70},1)
        imgui.set_next_window_size({900,360},1)
        position_window=false
    end
    imgui.push_font(_G.MHWAddSaveSlots_font)
    imgui.begin_window("Wilds - fourth character (experimental)",nil,0)
    local ok,err=pcall(function()
        imgui.text("Characters: "..view.slots.." | Current index: "..view.current)
        imgui.text(message)
        imgui.text("Open Start Game / Select Saved Data, then use this selector.")
        imgui.text("Offline test copy only. Clone retains source online identity.")
        imgui.begin_disabled(not view.enabled or pending~=nil)
        if view.slots==3 and imgui.button("Create Gupta + Kirikau as character 4") then pending="append_clone" end
        if view.slots==4 and imgui.button("Load Gupta + Kirikau (character 4)") then pending="load_fourth" end
        imgui.end_disabled()
    end)
    if not ok then imgui.text(tostring(err)) end
    imgui.end_window()
    imgui.pop_font()
end
-- A single callback survives development module reloads without accumulating
-- duplicate windows. The current module owns the function it dispatches to.
_G.MHWAddSaveSlots_window=M.window
if not _G.MHWAddSaveSlots_window_registered then
    _G.MHWAddSaveSlots_window_registered=true
    re.on_frame(function() if _G.MHWAddSaveSlots_window then _G.MHWAddSaveSlots_window() end end)
end
return M
