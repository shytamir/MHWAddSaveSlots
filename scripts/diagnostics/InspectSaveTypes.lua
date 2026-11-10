-- Development-only metadata inspection. Run once through REFramework's
-- ScriptRunner > Run script, with a verified copied-save session unarmed.
-- Reads type metadata only; no game methods, save requests, or field writes.
local finished=false
local message="Waiting for the game update callback"
local function inspect()
    local session=json.load_file("MHWAddSaveSlots.session.json")
    assert(session and session.isolated==true and session.mutation_enabled==false,
        "This probe requires an isolated, unarmed copied-save session")
    local root=assert(sdk.find_type_definition("System.Object"))
    local types=root:get_types_inheriting_from_this()
    local report={version=1,utc=os.date("!%Y-%m-%dT%H:%M:%SZ"),
        scope="Type metadata only; no game API invocation",scanned=#types,types={}}
    local selected={}
    local function interesting(name)
        local lower=name:lower()
        return name:find("^via%.storage%.") or
            (name:find("^via%.") and (lower:find("serial",1,true) or lower:find("stream",1,true)))
    end
    for _,td in ipairs(types) do
        local name=td:get_full_name()
        if interesting(name) then selected[#selected+1]=td end
    end
    for _,td in ipairs(selected) do
        local name=td:get_full_name()
        local parent=td:get_parent_type()
        local entry={name=name,parent=parent and parent:get_full_name(),
            value_type=td:is_value_type(),enum=td:is_enum(),fields={},methods={}}
        for _,f in ipairs(td:get_fields()) do
            entry.fields[#entry.fields+1]={name=f:get_name(),type=f:get_type():get_full_name(),
                static=f:is_static(),offset=f:get_offset_from_base()}
        end
        for _,m in ipairs(td:get_methods()) do
            local params={}
            for _,p in ipairs(m:get_param_types()) do params[#params+1]=p:get_full_name() end
            entry.methods[#entry.methods+1]={name=m:get_name(),parameters=params,
                returns=m:get_return_type():get_full_name(),static=m:is_static(),address=tostring(m:get_function())}
        end
        report.types[name]=entry
    end
    report.selected=#selected
    assert(json.dump_file("MHWAddSaveSlots.save-api-types.json",report)~=false,"Report write failed")
    message="Metadata captured: "..#selected.." storage/serialization/stream types"
    log.info("MHWAddSaveSlots: "..message)
end
re.on_application_entry("UpdateBehavior",function()
    if finished then return end
    finished=true
    local ok,err=pcall(inspect)
    if not ok then message=tostring(err); log.error("MHWAddSaveSlots metadata: "..message) end
end)
re.on_draw_ui(function()
    if imgui.tree_node("Wilds save API investigation") then
        imgui.text(message)
        imgui.tree_pop()
    end
end)
