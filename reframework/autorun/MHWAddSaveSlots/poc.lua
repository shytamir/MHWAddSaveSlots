local M={}
local control=require("MHWAddSaveSlots.control")
local policy=require("MHWAddSaveSlots.policy")
local records=require("MHWAddSaveSlots.records")
local safety
function M.configure(backend) safety=assert(backend) end
local pending,last_poll=nil,0
local message="Experimental character library: copied saves only"
local view={slots={},isolated=false,title=false}
local clone_source,hunter,palico=1,"Gupta","Kirikau"
local font=imgui.load_font(nil,28)
local position_window=true
local archive_index,archive_entry=1,1
local activation_confirm=false
local stale=control.read("command")
local processed={}
if stale.id and stale.session_id then processed[stale.session_id..":"..stale.id]=true end
local function guard()
    safety.guard()
    local manager,root,slots,state=records.context()
    assert(state and state:get_type_definition():get_full_name()=="app.TitleState","Return to Select Saved Data")
    assert(not records.busy(manager),"Save/load flow is busy")
    policy.count(slots:get_size())
    return manager,root,slots
end
local function select_character(index, fresh)
    local manager,_,slots=guard()
    policy.index(index,slots:get_size())
    local record=slots:get_element(index)
    assert(record,"Missing character")
    assert((record:get_field("Active")==0)==fresh,fresh and "Entry already contains a character" or "Entry is empty")
    local guis=sdk.get_managed_singleton("app.GUIManager"):get_field("_AllGUI")
    local selector
    for i=0,guis:get_size()-1 do
        local g=guis:get_element(i)
        if g and g:get_type_definition():get_full_name()=="app.GUI010102" then selector=g; break end
    end
    assert(selector and selector:get_field("_BaseState")==2,"Open Start Game / Select Saved Data first")
    local list=assert(selector:get_field("_DataList"))
    list:call("set_ItemCount",slots:get_size())
    list:call("set_SelectedIndex",index)
    assert(list:call("get_SelectedIndex")==index,"Native controller rejected selection")
    manager:set_field("CurrentUserDataIndex",index)
    assert(manager:call("getCurrentUserSaveData")==record,"Current-save accessor returned a different record")
    selector:call("selectFinish")
    message=fresh and "Requested the native new-character flow for the empty entry" or "Requested character "..(index+1)
end
local function append(request, fresh)
    local manager,root,slots=guard()
    local count=slots:get_size()
    assert(count<policy.MAX_SLOTS,"Experimental capacity limit reached")
    local record=records.new()
    if fresh then
        assert(record:get_field("Active")==0,"Initializer did not produce an empty record; refusing attachment")
    else
        local source_index=policy.index((request.source or 1)-1,count)
        local source=slots:get_element(source_index)
        assert(source:get_field("Active")~=0,"Clone source is empty")
        assert(record:call("copyFrom(ace.cSaveDataBase)",source)==true,"Game rejected clone")
        local original,n=records.audit(source)
        local _,m=records.audit(record,original)
        local basic=record:get_field("_BasicData")
        local name=request.hunter or "Gupta"
        local cat=request.palico or "Kirikau"
        assert(type(name)=="string" and #name>0 and #name<=48 and type(cat)=="string" and #cat>0 and #cat<=48,"Invalid clone names")
        basic:set_field("CharName",sdk.create_managed_string(name))
        basic:set_field("OtomoName",sdk.create_managed_string(cat))
        control.write("clone-test",{source_objects=n,clone_objects=m,shared_mutable_objects=0,index=count})
    end
    local expanded=records.array(slots,count+1)
    expanded[count]=record
    local previous=manager:get_field("CurrentUserDataIndex")
    local ok,err=pcall(function()
        root:set_field("_Data",expanded)
        manager:set_field("CurrentUserDataIndex",count)
        assert(manager:call("getCurrentUserSaveData")==record,"New entry is not addressable")
    end)
    manager:set_field("CurrentUserDataIndex",previous)
    if not ok then root:set_field("_Data",slots); error(err) end
    -- Startup capacity is committed by the companion ONLY after a successful
    -- native save and verified snapshot, never from an in-memory allocation.
    message=fresh and "Empty entry added. Choose Create new to open the native editor." or "Clone attached. Load it and save normally."
end
local actions={
    activate=function() safety.activate(); message="Library enabled. Initial character snapshot verified."; activation_confirm=false end,
    restore=function(r)
        local index=safety.restore_character(r.snapshot,r.entry)
        message="Recovered into entry "..(index+1)..". Load it and save normally."
    end,
    append_clone=function(r) append(r,false) end,
    append_fresh=function(r) append(r,true) end,
    load=function(r) select_character(assert(r.index),false) end,
    create_new=function(r) select_character(assert(r.index),true) end,
    prepare_trim=function() safety.prepare_trim(); message="Saving the expanded container before trim" end,
    confirm_trim=function() safety.confirm_trim(); message="Waiting for durable trim journal" end,
    cancel_trim=function() safety.cancel_trim(); message="Trim cancelled" end,
}
function M.update()
    if os.clock()-last_poll>0.5 then
        last_poll=os.clock()
        local session=control.read("session")
        local manager,_,slots,state=records.context()
        view.isolated=session.isolated==true or (safety.enabled and safety.enabled())
        view.enabled=safety.enabled and safety.enabled() or control.enabled(session)
        view.title=state and state:get_type_definition():get_full_name()=="app.TitleState"
        view.current=manager and manager:get_field("CurrentUserDataIndex") or -1
        view.slots={}
        if slots then
            for i=0,slots:get_size()-1 do
                local record=slots:get_element(i)
                local basic=record and record:get_field("_BasicData")
                view.slots[#view.slots+1]={index=i,active=record and record:get_field("Active")~=0,
                    name=basic and basic:get_field("CharName") or "Empty"}
            end
        end
        local req=control.read("command")
        if req.session_id==session.session_id and req.id and not processed[req.session_id..":"..req.id] then
            processed[req.session_id..":"..req.id]=true; pending=req
        end
    end
    if pending then
        local request=pending; pending=nil
        local ok,err=pcall(function() assert(actions[request.action],"Unknown action")(request) end)
        if not ok then message=tostring(err) end
        control.write("result",{action=request.action,ok=ok,message=message,id=request.id})
    end
end
local function panel()
    local status,event,trim,fault=safety.state()
    imgui.text(message)
    imgui.text("Characters: "..#view.slots.." / "..policy.MAX_SLOTS.." | Current index: "..tostring(view.current))
    imgui.text(fault or status.error or (status.ready and "Local backups ready" or "Read-only: library not enabled"))
    if status.notice then imgui.text(status.notice) end
    if event then imgui.text("Last save: "..event.phase..(status.ack==event.id and " / backup verified" or " / awaiting backup")) end
    if trim then imgui.text("Trim: "..trim.stage) end
    imgui.text("Copied saves only. Clones retain source online identity.")
    local input_open=reframework:is_drawing_ui()
    if not input_open then imgui.text("Press Insert to interact with this selector.") end
    if not view.enabled and safety.activate then
        imgui.text("First setup requires a separate three-character save copy and Steam Cloud disabled.")
        imgui.begin_disabled(not input_open or not view.title or pending~=nil)
        if not activation_confirm then
            if imgui.button("Set up this copied save") then activation_confirm=true end
        else
            imgui.text("Confirm that your originals are preserved separately and this is a test copy.")
            if imgui.button("Confirm copied save and enable") then pending={action="activate"} end
            if imgui.button("Cancel setup") then activation_confirm=false end
        end
        imgui.end_disabled()
    end
    imgui.begin_disabled(not input_open or not view.enabled or pending~=nil or fault~=nil)
    if view.title then
        for _,slot in ipairs(view.slots) do
            local label=(slot.active and "Load " or "Create new in ")..(slot.index+1)..": "..tostring(slot.name).."##slot"..slot.index
            if imgui.button(label) then pending={action=slot.active and "load" or "create_new",index=slot.index} end
        end
        if #view.slots<policy.MAX_SLOTS then
            if imgui.button("Add empty entry for a fresh character") then pending={action="append_fresh"} end
            local changed
            changed,clone_source=imgui.slider_int("Clone source",clone_source,1,math.max(1,#view.slots))
            changed,hunter=imgui.input_text("Clone hunter name",hunter)
            changed,palico=imgui.input_text("Clone Palico name",palico)
            if imgui.button("Add independent clone") then pending={action="append_clone",source=clone_source,hunter=hunter,palico=palico} end
        end
        if safety.catalog then
            local catalog=safety.catalog()
            local room=#view.slots<policy.MAX_SLOTS
            for _,slot in ipairs(view.slots) do if slot.index>=3 and not slot.active then room=true end end
            if #catalog>0 and room and imgui.tree_node("Recover an archived character") then
                archive_index=math.max(1,math.min(archive_index,#catalog))
                local changed
                changed,archive_index=imgui.slider_int("Snapshot (1 is newest)",archive_index,1,#catalog)
                local selected=catalog[archive_index]
                imgui.text(tostring(selected.utc).." | "..selected.slots.." entries | "..tostring(selected.label))
                imgui.text(selected.committed and "Native save completed" or "Captured before a save or change; completion unconfirmed")
                archive_entry=math.max(1,math.min(archive_entry,selected.slots))
                changed,archive_entry=imgui.slider_int("Character in snapshot",archive_entry,1,selected.slots)
                if imgui.button("Restore into an extra entry") then pending={action="restore",snapshot=selected.id,entry=archive_entry-1} end
                imgui.tree_pop()
            end
        end
    end
    if not trim or trim.stage=="complete" or trim.stage=="cancelled" then
        if #view.slots>3 and imgui.button("Prepare trim: save and back up all characters") then pending={action="prepare_trim"} end
    elseif trim.stage=="ready" then
        imgui.text("Expanded backup verified. Keep only entries 1-3 in the active test save?")
        if imgui.button("Confirm trim to three characters") then pending={action="confirm_trim"} end
        if imgui.button("Cancel trim") then pending={action="cancel_trim"} end
    elseif trim.stage=="backing-up" then
        if imgui.button("Cancel trim preparation") then pending={action="cancel_trim"} end
    end
    imgui.end_disabled()
end
function M.draw()
    if font then imgui.push_font(font) end
    if imgui.tree_node("Wilds expanded characters") then
        local ok,err=pcall(panel)
        if not ok then imgui.text(tostring(err)) end
        imgui.tree_pop()
    end
    if font then imgui.pop_font() end
end
re.on_frame(function()
    if not view.isolated or not view.title then return end
    if position_window then
        imgui.set_next_window_pos({70,70},1)
        imgui.set_next_window_size({1100,700},1)
        position_window=false
    end
    if font then imgui.push_font(font) end
    imgui.begin_window("Wilds expanded characters (experimental)",nil,0)
    local ok,err=pcall(panel)
    if not ok then imgui.text(tostring(err)) end
    imgui.end_window()
    if font then imgui.pop_font() end
end)
return M
