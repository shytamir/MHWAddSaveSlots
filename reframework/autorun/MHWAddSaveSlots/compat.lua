-- The tested build allocates three-entry destinations for saves and startup
-- loads. Expand those destinations only for an explicitly armed test session.
-- Startup additionally requires matching four-slot capacity metadata.
local M={}
local control=require("MHWAddSaveSlots.control")
local session=control.read("session")
local function enabled()
    return control.enabled(session)
end
local last_poll=0
local stats={expanded_copies=0,expanded_loads=0,started_utc=os.date("!%Y-%m-%dT%H:%M:%SZ")}
local function expand(target)
    local old=assert(target:get_field("_Data"),"Missing character array")
    if old:get_size()==4 then return end
    assert(old:get_size()==3,"Unexpected character array size")
    local expanded=assert(sdk.create_managed_array("app.savedata.cUserSaveParam",4))
    expanded:add_ref()
    for i=0,2 do expanded[i]=old:get_element(i) end
    local fourth=assert(sdk.find_type_definition("app.savedata.cUserSaveParam"):get_method("create"):call(nil))
    fourth:add_ref()
    fourth:call("init")
    expanded[3]=fourth
    target:set_field("_Data",expanded)
end
local function write_stats()
    json.dump_file("MHWAddSaveSlots.compat-result.json",stats)
end
function M.update()
    if os.clock()-last_poll>1 then
        last_poll=os.clock()
        session=control.read("session")
    end
end
function M.draw() end
_G.MHWAddSaveSlots_copy_pre=function(args)
    if not enabled() then return end
    local target=sdk.to_managed_object(args[2])
    local source=sdk.to_managed_object(args[3])
    local source_array=source and source:get_field("_Data")
    local target_array=target and target:get_field("_Data")
    if not source_array or not target_array or source_array:get_size()~=4 or target_array:get_size()~=3 then return end
    expand(target)
    stats.expanded_copies=stats.expanded_copies+1
    write_stats()
end
_G.MHWAddSaveSlots_load_pre=function(args)
    if not enabled() then return end
    local native=control.read("native")
    if native.session_id~=session.session_id or native.slots~=4 then return end
    local manager=sdk.to_managed_object(args[2])
    expand(assert(manager:get_field("_UserSaveData")))
    stats.expanded_loads=stats.expanded_loads+1
    write_stats()
end
_G.MHWAddSaveSlots_after_load=function(args)
    if not enabled() then return end
    local root=sdk.to_managed_object(args[2])
    local array=root:get_field("_Data")
    stats.loaded_count=array:get_size()
    local fourth=array:get_size()>3 and array:get_element(3)
    local basic=fourth and fourth:get_field("_BasicData")
    stats.loaded_fourth=basic and basic:get_field("CharName") or nil
    stats.loaded_utc=os.date("!%Y-%m-%dT%H:%M:%SZ")
    write_stats()
end
if not _G.MHWAddSaveSlots_compat_registered then
    local user=sdk.find_type_definition("app.savedata.cUserSaveData")
    assert(user,"Compatibility type unavailable")
    sdk.hook(user:get_method("copyFrom(ace.cSaveDataBase)"),function(args)
        return _G.MHWAddSaveSlots_copy_pre(args)
    end,function(retval) return retval end)
    _G.MHWAddSaveSlots_compat_registered=true
end
if not _G.MHWAddSaveSlots_load_registered then
    local manager=assert(sdk.find_type_definition("app.SaveDataManager"))
    sdk.hook(assert(manager:get_method("systemRequestUserLoad")),function(args)
        return _G.MHWAddSaveSlots_load_pre(args)
    end,function(retval) return retval end)
    local user=assert(sdk.find_type_definition("app.savedata.cUserSaveData"))
    sdk.hook(assert(user:get_method("setupAfterLoad")),function(args)
        return _G.MHWAddSaveSlots_after_load(args)
    end,function(retval) return retval end)
    _G.MHWAddSaveSlots_load_registered=true
end
return M
