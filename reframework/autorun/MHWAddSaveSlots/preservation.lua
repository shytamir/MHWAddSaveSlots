-- In-process preservation using engine snapshots and immutable REFramework files.
local M={}
local control=require("MHWAddSaveSlots.control")
local policy=require("MHWAddSaveSlots.policy")
local records=require("MHWAddSaveSlots.records")
local archive=require("MHWAddSaveSlots.archive")
local codec=require("MHWAddSaveSlots.snapshot_codec")
local session=control.read("session")
local testing=control.enabled(session)
local activation_path="MHWAddSaveSlots/activation.json"
local activation_file=io.open(activation_path,"rb")
local activation_present=activation_file~=nil
if activation_file then activation_file:close() end
local activation
if activation_present then
    local ok,value=pcall(json.load_file,activation_path)
    if ok and type(value)=="table" then activation=value end
end
local protected=testing or (activation_present and (not activation or activation.enabled~=false))
local store
local runtime_id=tostring(os.time()).."-"..tostring(math.random(100000,999999))
local event,trim,fault=nil,nil,nil
local deferred_load
local sequence,last_poll,last_native=0,0,0
local status={ready=false,slots=3}
local function read_status()
    status.ready=protected and store~=nil and fault==nil
    status.error=fault
    if store then
        status.slots=store:capacity()
        status.snapshot=store.committed and store.committed.id or store.latest and store.latest.id
    end
    return status
end
if protected then
    local ok,err=pcall(function()
        assert(testing or (type(activation)=="table" and activation.version==1 and activation.copy_acknowledged==true),"Activation record is damaged")
        store=archive.open(testing and ("test-"..session.session_id) or activation.profile)
        assert(testing or store.latest~=nil,"Backup library is missing; restore the complete reframework/data/MHWAddSaveSlots folder")
    end)
    if not ok then fault=tostring(err) end
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
local function ready()
    read_status()
    assert(status.ready,status.error or "Enable Add Save Slots first")
    policy.count(status.slots)
    assert(not event or event.phase~="writing","Waiting for the previous native save")
    return status
end
local function capture(slots,label)
    local entries={}
    for i=0,policy.count(slots:get_size())-1 do entries[#entries+1]=codec.encode(assert(slots:get_element(i))) end
    return store:capture(entries,label)
end
local function receipt(stage)
    local record={version=3,session_id=session.session_id,runtime_id=runtime_id,event=event}
    control.write("save-"..stage.."-"..event.id,record)
    control.write("latest-save",record)
end
function M.guard()
    assert(protected,"Enable Add Save Slots first")
    if testing then assert(control.enabled(control.read("session")),"The copied-save test session has expired") end
    assert(not fault,fault)
    assert(not trim or trim.stage=="complete" or trim.stage=="cancelled","Trim transaction in progress")
    return ready()
end
function M.state() return status,event,trim,fault end
function M.enabled() return protected end
function M.catalog() return store and store.catalog or {} end
function M.activate()
    assert(not protected,"Library is already enabled")
    local manager,_,slots,state=records.context()
    assert(state and state:get_type_definition():get_full_name()=="app.TitleState" and not records.busy(manager),"Open Select Saved Data first")
    assert(slots:get_size()==3,"First setup requires three native save slots")
    local profile="profile-"..id()
    store=archive.open(profile)
    local baseline=capture(slots,"initial character snapshot")
    store:commit(baseline.id)
    local value={version=1,enabled=true,copy_acknowledged=true,profile=profile}
    assert(json.dump_file(activation_path,value)~=false,"Could not store activation")
    local check=json.load_file(activation_path)
    assert(check and check.profile==profile and check.enabled==true,"Activation read-back failed")
    protected=true; read_status(); emit()
end
function M.restore_character(snapshot_id,entry_index)
    M.guard()
    local manager,root,slots,state=records.context()
    assert(state and state:get_type_definition():get_full_name()=="app.TitleState" and not records.busy(manager),"Open Select Saved Data first")
    local count=slots:get_size()
    local destination
    for i=3,count-1 do if slots:get_element(i):get_field("Active")==0 then destination=i;break end end
    if not destination then assert(count<policy.MAX_SLOTS,"Character limit reached");destination=count end
    local snapshot=store:load(snapshot_id)
    policy.index(entry_index,#snapshot.entries)
    capture(slots,"before character recovery")
    local restored=codec.decode(snapshot.entries[entry_index+1])
    for i=0,count-1 do local seen=records.audit(slots:get_element(i)); records.audit(restored,seen) end
    local expanded=records.array(slots,math.max(count,destination+1)); expanded[destination]=restored
    root:set_field("_Data",expanded)
    return destination
end
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
do
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
            local manager,live,_,state=records.context()
            local native_load=target==live and state and state:get_type_definition():get_full_name()=="app.TitleState"
            if native_load then
                storage.loaded_target=target
                storage.reserve_count=store and store:capacity() or count
                stats.smaller_native_load=count
                status.notice="Some extra entries may be empty. Earlier snapshots remain available for recovery."
            else
                assert(count==3 and trim and (trim.stage=="saving" or trim.stage=="complete"),"Unexpected shrinking save copy refused")
            end
        end
        if old~=count then records.resize(target,count); stats.expanded_copies=stats.expanded_copies+1 end
    end)
    if not ok then storage.rejected=true; fail(err); return sdk.PreHookResult.SKIP_ORIGINAL end
end,function(retval)
    local storage=thread.get_hook_storage()
    if storage.rejected then return sdk.to_ptr(false) end
    if storage.loaded_target and storage.reserve_count and sdk.to_int64(retval)~=0 then
        local ok,err=pcall(records.resize,storage.loaded_target,storage.reserve_count)
        if not ok then fail(err);return sdk.to_ptr(false) end
    end
    return retval
end)
sdk.hook(method("app.SaveDataManager","systemRequestUserLoad"),function(args)
    if not protected then return end
    -- A damaged archive must not trap the title screen behind a deferred load.
    -- Permit native inspection while the character-save hook remains fail-closed.
    if fault then stats.load_warning=fault; return end
    local ok,err=pcall(function()
        local current=ready()
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
        local current=ready()
        local count=policy.count(target:get_field("_Data"):get_size())
        if count<current.slots then
            assert(count==3 and trim and trim.stage=="saving" and trim.source==current.snapshot,"Capacity reduction requires a prepared trim")
        end
        local snapshot=capture(target:get_field("_Data"),trim and trim.stage=="saving" and "before native trim save" or "before native character save")
        event={id=id(),request=key,phase="writing",slots=count,purpose=trim and trim.stage=="saving" and "trim" or "save",
            trim_id=trim and trim.id or nil,snapshot=snapshot.id}
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
        if event.phase=="completed" then
            store:commit(event.snapshot)
            status.ack=event.id
            read_status()
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
    assert(protected,"Library is not enabled")
    assert(not fault,fault)
    local current=ready()
    local manager,_,_,state=records.context()
    assert(state and state:get_type_definition():get_full_name()=="app.IngameState" and not records.busy(manager),"Load a native character and wait for saves to finish")
    assert(trim and trim.stage=="ready","Prepare the expanded backup first")
    assert(event and event.phase=="completed" and current.ack==event.id and current.slots==trim.count,"Expanded save backup is not current")
    trim.source=current.snapshot; trim.stage="awaiting-journal"
    -- The immutable expanded snapshot is already verified and retained. Read it
    -- again before allowing the in-memory/native container to shrink.
    assert(store:load(trim.source).slots==trim.count,"Expanded trim snapshot differs")
    status.trim_ack=trim.id
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
    if deferred_load and (status.ready or fault) then
        local waiting=deferred_load
        deferred_load=nil
        local ok,err=pcall(function() waiting.manager:call("systemRequestUserLoad",waiting.callback) end)
        if not ok then stats.load_wait=tostring(err) end
    end
    if trim and not records.busy(manager) then
        if trim.stage=="backing-up" and event and event.id~=trim.baseline and event.phase=="completed" and status.ack==event.id and status.slots==trim.count then
            trim.stage="ready"
        elseif trim.stage=="awaiting-journal" and status.trim_ack==trim.id then
            local ok,err=pcall(function()
                ready()
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
