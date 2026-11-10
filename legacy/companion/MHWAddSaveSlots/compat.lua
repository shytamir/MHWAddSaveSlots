-- Preservation hooks stay latched for an armed process if its creation lease expires.
local M={}
local control=require("MHWAddSaveSlots.control")
local policy=require("MHWAddSaveSlots.policy")
local records=require("MHWAddSaveSlots.records")
local session=control.read("session")
local protected=control.enabled(session)
local runtime_id=tostring(os.time()).."-"..tostring(math.random(100000,999999))
local event,trim,fault=nil,nil,nil
local deferred_load
local sequence,last_poll,last_native=0,0,0
local status={}
local function read_status()
    local next_status=control.read("companion")
    -- Atomic replacement can briefly fail to open on Windows. Retain only an
    -- already validated, still-expiring heartbeat; never invent readiness.
    if next_status.session_id==session.session_id and type(next_status.heartbeat)=="number" then status=next_status end
    return status
end
local stats={index_repairs=0,expanded_copies=0,expanded_loads=0,runtime_id=runtime_id}
local function id()
    sequence=sequence+1
    return runtime_id.."-"..sequence
end
local function emit()
    local manager,_,slots=records.context()
    control.write("runtime",{version=2,session_id=session.session_id,runtime_id=runtime_id,
        heartbeat=os.time(),busy=manager and records.busy(manager) or false,
        slots=slots and slots:get_size() or 0,event=event,trim=trim,fault=fault,
        last_native=last_native,stats=stats})
end
local function fail(err)
    fault=tostring(err)
    log.error("MHWAddSaveSlots: "..fault)
    pcall(emit)
end
local function companion()
    read_status()
    assert(policy.ready(status,session.session_id,os.time()),status.error or "Backup companion is not ready")
    policy.count(status.slots)
    local latest=control.read("latest-save")
    if latest.session_id==session.session_id and latest.event then
        assert(latest.event.phase~="writing","Waiting for the previous save to finish")
        if latest.event.phase=="completed" then
            assert(status.ack==latest.event.id,"Waiting for the previous save's durable backup")
        end
    end
    return status
end
local function receipt(stage)
    local record={version=3,session_id=session.session_id,runtime_id=runtime_id,event=event}
    control.write("save-"..stage.."-"..event.id,record)
    control.write("latest-save",record)
end
function M.guard()
    assert(protected and control.enabled(control.read("session")),"Arm an isolated test session before starting Wilds")
    assert(not fault,fault)
    assert(not trim or trim.stage=="complete" or trim.stage=="cancelled","Trim transaction in progress")
    return companion()
end
function M.state() return status,event,trim,fault end
function M.clamp(common)
    if not protected or not common then return end
    local old=common:get_field("LastUserIndex")
    local safe=policy.native_index(old,last_native)
    if old~=safe then
        common:set_field("LastUserIndex",safe)
        assert(common:get_field("LastUserIndex")==safe,"Persisted selection repair failed")
        stats.index_repairs=stats.index_repairs+1
    end
    -- CurrentUserDataIndex deliberately remains untouched here.
end
local function method(type_name, name)
    return assert(assert(sdk.find_type_definition(type_name),type_name):get_method(name),type_name.."."..name)
end
local function enum_value(type_name, names)
    local td=assert(sdk.find_type_definition(type_name),type_name)
    for _,field in ipairs(td:get_fields()) do
        if field:is_static() and names[field:get_name():upper()] then return field:get_data(nil) end
    end
    error("Unrecognized success enum: "..type_name.."; capture metadata before proceeding")
end
local success,no_error,rejected_error
local rejected_requests={}
if protected then
    success=enum_value("ace.SaveDataManagerBase.EXECUTE_RESULT",{SUCCESS=true,SUCCEEDED=true,OK=true})
    no_error=enum_value("ace.SaveDataManagerBase.ERROR_TYPE",{NONE=true,NO_ERROR=true,SUCCESS=true,OK=true})
    rejected_error=enum_value("ace.SaveDataManagerBase.ERROR_TYPE",{UNKNOWN=true})
end
sdk.hook(method("app.savedata.cUserSaveData","copyFrom(ace.cSaveDataBase)"),function(args)
    if not protected then return end
    local storage=thread.get_hook_storage()
    local ok,err=pcall(function()
        local target=assert(sdk.to_managed_object(args[2]))
        local source=assert(sdk.to_managed_object(args[3]))
        local count=policy.count(source:get_field("_Data"):get_size())
        local old=target:get_field("_Data"):get_size()
        if old>count then
            assert(count==3 and trim and (trim.stage=="saving" or trim.stage=="complete"),"Unexpected shrinking save copy refused")
        end
        if old~=count then records.resize(target,count); stats.expanded_copies=stats.expanded_copies+1 end
    end)
    if not ok then storage.rejected=true; fail(err); return sdk.PreHookResult.SKIP_ORIGINAL end
end,function(retval)
    if thread.get_hook_storage().rejected then return sdk.to_ptr(false) end
    return retval
end)
sdk.hook(method("app.SaveDataManager","systemRequestUserLoad"),function(args)
    if not protected then return end
    local ok,err=pcall(function()
        local current=companion()
        local manager=assert(sdk.to_managed_object(args[2]))
        records.resize(assert(manager:get_field("_UserSaveData")),current.slots)
        stats.expanded_loads=stats.expanded_loads+1
        deferred_load=nil; stats.load_wait=nil
    end)
    if not ok then
        if not deferred_load then
            local manager=assert(sdk.to_managed_object(args[2])); manager:add_ref()
            local callback=sdk.to_managed_object(args[3])
            if callback then callback:add_ref() end
            deferred_load={manager=manager,callback=callback}
        end
        stats.load_wait=tostring(err)
        return sdk.PreHookResult.SKIP_ORIGINAL
    end
end,function(retval) return retval end)
-- Clamp the actual serialization object, including staging copies.
for _,name in ipairs({"runSaveDataCore","setupBeforeSave","copyFrom(ace.cSaveDataBase)"}) do
    local returns_bool=name~="setupBeforeSave"
    sdk.hook(method("app.savedata.cSystemCommonParam",name),function(args)
        if not protected then return end
        local storage=thread.get_hook_storage()
        local ok,err=pcall(function()
            storage.common=assert(sdk.to_managed_object(args[2]),"Missing system serialization object")
            M.clamp(storage.common)
        end)
        if not ok then storage.rejected=true; fail(err); return sdk.PreHookResult.SKIP_ORIGINAL end
    end,function(retval)
        local storage=thread.get_hook_storage()
        local ok,err=pcall(M.clamp,storage.common)
        if not ok then storage.rejected=true; fail(err) end
        if storage.rejected and returns_bool then return sdk.to_ptr(false) end
        return retval
    end)
end
sdk.hook(method("app.SaveDataManager","systemRequestSystemSave"),function(args)
    if protected then M.clamp(records.common(sdk.to_managed_object(args[2]))) end
end,function(retval) return retval end)
-- This virtual execution boundary is used even by startup paths which bypass
-- the requestSave convenience method. The inspected native implementation
-- returns ERROR_TYPE.UNKNOWN when the underlying save service refuses a start.
sdk.hook(method("ace.SaveDataManagerBase.cSaveRequest","execMainFunction"),function(args)
    if not protected then return end
    local storage=thread.get_hook_storage()
    local request=sdk.to_managed_object(args[2])
    if not request or request:get_type_definition():get_full_name()~="ace.SaveDataManagerBase.cSaveRequest" then return end
    local key=tostring(request:get_address())
    rejected_requests[key]=nil -- A freed request address may be reused later.
    local target=request:call("get_Target")
    if not target then return end
    local kind=target:get_type_definition():get_full_name()
    if kind~="app.savedata.cUserSaveData" and kind~="app.savedata.cSystemSaveData" then return end
    local ok,err=pcall(function()
        assert(not fault,fault)
        if kind=="app.savedata.cSystemSaveData" then
            M.clamp(target:get_field("_Data"):get_field("_SystemCommon"))
            return
        end
        local current=companion()
        local count=policy.count(target:get_field("_Data"):get_size())
        local ticket=trim and trim.stage=="saving" and {runtime_id=trim.runtime_id,source=trim.source,id=trim.id,stage="prepared"}
        policy.can_save(count,current,event,runtime_id,ticket)
        event={id=id(),request=key,phase="writing",slots=count,purpose=trim and trim.stage=="saving" and "trim" or "save",
            trim_id=trim and trim.id or nil}
        storage.event_id=event.id
        receipt("start") -- Survives process exit and the next runtime's heartbeat.
        emit()
    end)
    if not ok then
        rejected_requests[key]=true
        storage.rejected=true; stats.last_refusal=tostring(err); pcall(emit)
        return sdk.PreHookResult.SKIP_ORIGINAL
    end
end,function(retval)
    local storage=thread.get_hook_storage()
    if storage.rejected then return sdk.to_ptr(rejected_error) end
    if storage.event_id and event and event.id==storage.event_id and sdk.to_int64(retval)~=no_error then
        event.phase="failed"; event.error=sdk.to_int64(retval)
        local ok,err=pcall(receipt,"end"); if not ok then fail(err) end
        pcall(emit)
    end
    return retval
end)
sdk.hook(method("ace.SaveDataManagerBase.cSaveRequest","execCallback"),function(args)
    if not protected then return end
    local ok,err=pcall(function()
        local request=assert(sdk.to_managed_object(args[2]))
        if request:get_type_definition():get_full_name()~="ace.SaveDataManagerBase.cSaveRequest" then return end
        local key=tostring(request:get_address())
        if rejected_requests[key] then rejected_requests[key]=nil; return end
        local target=request:call("get_Target")
        if not target or target:get_type_definition():get_full_name()~="app.savedata.cUserSaveData" then return end
        assert(event and event.request==key and (event.phase=="writing" or event.phase=="failed"),"Untracked character-save completion")
        assert(target:get_field("_Data"):get_size()==event.slots,"Save destination capacity changed")
        if event.phase~="failed" then
            event.result=sdk.to_int64(args[3]); event.error=sdk.to_int64(args[4])
            event.phase=event.result==success and event.error==no_error and "completed" or "failed"
        end
        receipt("end")
        emit()
    end)
    if not ok then fail(err) end
end,function(retval) return retval end)
function M.prepare_trim()
    M.guard()
    local manager,_,slots,state=records.context()
    assert(state and state:get_type_definition():get_full_name()=="app.IngameState","Load a native character first")
    assert(not records.busy(manager),"Save flow is busy")
    local index=manager:get_field("CurrentUserDataIndex")
    assert(slots:get_size()>3 and index>=0 and index<3,"Load one of the first three characters before trimming")
    trim={id=id(),runtime_id=runtime_id,stage="backing-up",count=slots:get_size(),baseline=event and event.id or ""}
    emit()
    manager:call("requestSaveDataManualSave",nil)
end
function M.confirm_trim()
    assert(protected and control.enabled(control.read("session")),"Session is not armed")
    assert(not fault,fault)
    local current=companion()
    local manager,_,_,state=records.context()
    assert(state and state:get_type_definition():get_full_name()=="app.IngameState" and not records.busy(manager),"Load a native character and wait for saves to finish")
    assert(trim and trim.stage=="ready","Prepare the expanded backup first")
    assert(event and event.phase=="completed" and current.ack==event.id and current.slots==trim.count,"Expanded save backup is not current")
    trim.source=current.snapshot; trim.stage="awaiting-journal"
    emit()
end
function M.cancel_trim()
    assert(trim and (trim.stage=="ready" or trim.stage=="backing-up"),"Cannot cancel a committed trim")
    trim.stage="cancelled"; emit()
end
local retained
function M.update()
    if not protected then return end
    local manager,root,slots=records.context()
    if not manager or not slots then return end
    local index=manager:get_field("CurrentUserDataIndex")
    if index>=0 and index<3 then last_native=index end
    M.clamp(records.common(manager))
    if os.clock()-last_poll<0.5 then return end
    last_poll=os.clock(); read_status()
    if deferred_load and policy.ready(status,session.session_id,os.time()) then
        local waiting=deferred_load
        local ok,err=pcall(function() waiting.manager:call("systemRequestUserLoad",waiting.callback) end)
        if not ok then stats.load_wait=tostring(err) end
    end
    if trim and not records.busy(manager) then
        if trim.stage=="backing-up" and event and event.id~=trim.baseline and event.phase=="completed" and status.ack==event.id and status.slots==trim.count then
            trim.stage="ready"
        elseif trim.stage=="awaiting-journal" and status.trim_ack==trim.id then
            local ok,err=pcall(function()
                companion()
                assert(not fault,fault)
                assert(index>=0 and index<3,"Native character is no longer selected")
                assert(slots:get_size()==trim.count and status.snapshot==trim.source,"Trim source changed")
                retained=slots; retained:add_ref()
                root:set_field("_Data",records.array(slots,3))
                trim.stage="saving"; emit()
                manager:call("requestSaveDataManualSave",nil)
            end)
            if not ok then
                if retained then root:set_field("_Data",retained) end
                trim.stage="failed"; fail(err)
            end
        elseif trim.stage=="saving" and event and event.purpose=="trim" then
            if event.phase=="completed" and status.ack==event.id and status.slots==3 then
                trim.stage="complete"; retained=nil
            elseif event.phase=="failed" then
                if retained then root:set_field("_Data",retained) end
                trim.stage="failed"
                fail("Trim save failed. Expanded memory restored; inspect retained backups before restarting.")
            end
        end
    end
    emit()
end
function M.draw() end
M.registered=true
return M
