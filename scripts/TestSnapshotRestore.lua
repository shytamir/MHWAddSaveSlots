-- Development-only copied-save recovery test. No companion or expansion hooks.
-- A private request selects a snapshot and native target slot. Attach once at
-- the character selector; subsequent launches observe the native persisted file.
local control=require("MHWAddSaveSlots.control")
local records=require("MHWAddSaveSlots.records")
local session=control.read("session")
assert(control.enabled(session),"Snapshot restore test requires an armed isolated copy")
local request=control.read("restore-test-request")
assert(request.session_id==session.session_id and request.target_index==2)
assert(type(request.snapshot)=="string" and request.snapshot:match("^MHWAddSaveSlots%.character%-messagepack%.%d+T%d+Z%.json$"))
local boot=tostring(os.time()).."-"..tostring(math.random(100000,999999))
local journal=control.read("restore-test-journal")
if journal.session_id~=session.session_id then journal={session_id=session.session_id,stage="pending"} end
local report={boot=boot,session_id=session.session_id,save_completions={},observe_only=request.observe_only==true}
local function enum_value(name,wanted)
    for _,field in ipairs(assert(sdk.find_type_definition(name)):get_fields()) do
        if field:is_static() and wanted[field:get_name():upper()] then return field:get_data(nil) end
    end
    error("Required save-result enum missing: "..name)
end
report.expected_result=enum_value("ace.SaveDataManagerBase.EXECUTE_RESULT",{SUCCESS=true,SUCCEEDED=true,OK=true})
report.expected_error=enum_value("ace.SaveDataManagerBase.ERROR_TYPE",{NONE=true,NO_ERROR=true,SUCCESS=true,OK=true})
local serializer=assert(sdk.find_type_definition("via.Serializer"))
local convert=assert(sdk.find_type_definition("System.Convert"))
local encode=assert(convert:get_method("ToBase64String(System.Byte[])"))
local decode=assert(convert:get_method("FromBase64String(System.String)"))
local serialize=assert(serializer:get_method("serializeMessagePackInternal"))
local deserialize=assert(serializer:get_method("deserializeMessagePackInternal"))
local td=assert(sdk.find_type_definition("app.savedata.cUserSaveParam"))
local runtimeType=td:get_runtime_type()
local function encoded(value)
    local bytes=assert(serialize:call(nil,runtimeType,value,0)); bytes:add_ref()
    return encode:call(nil,bytes)
end
local function emit()
    control.write("restore-test-runtime",report)
    control.write("restore-test-boot-"..boot,report)
end
local function restore(root,slots)
    local dump=assert(json.load_file(request.snapshot))
    assert(dump.source_type==td:get_full_name() and dump.format=="engine-object-messagepack")
    assert(dump.byte_count>0 and dump.byte_count<64*1024*1024 and #dump.base64==4*math.ceil(dump.byte_count/3))
    local bytes=assert(sdk.create_managed_array("System.Byte",dump.byte_count)); bytes:add_ref()
    local copy=assert(sdk.find_type_definition("System.Array"):get_method("Copy(System.Array, System.Int32, System.Array, System.Int32, System.Int32)"))
    local offset=0
    for first=1,#dump.base64,4096 do
        local part=assert(decode:call(nil,dump.base64:sub(first,first+4095))); part:add_ref()
        assert(offset+part:get_size()<=dump.byte_count)
        copy:call(nil,part,0,bytes,offset,part:get_size()); offset=offset+part:get_size()
    end
    assert(offset==dump.byte_count and encode:call(nil,bytes)==dump.base64)
    local restored=assert(deserialize:call(nil,runtimeType,bytes,0)); restored:add_ref()
    assert(restored:get_type_definition()==td and encoded(restored)==dump.base64)
    assert(restored:get_address()~=slots:get_element(0):get_address())
    -- A deserialized object round-trips but failed the first live load. Use the
    -- game's already-tested create/init/copyFrom path to initialize runtime data.
    journal.stage="initializing"; journal.boot=boot
    control.write("restore-test-journal",journal)
    local initialized=records.new()
    assert(initialized:call("copyFrom(ace.cSaveDataBase)",restored)==true,"Game rejected reconstructed source")
    -- Wilds' copyFrom omits these two arrays. Preserve their contents in the
    -- arrays allocated by init, then require equality of the entire record.
    local source_menu=assert(restored:get_field("_StartMenu"))
    local target_menu=assert(initialized:get_field("_StartMenu"))
    for _,name in ipairs({"RecentMenu","FavoriteMenu"}) do
        local source=assert(source_menu:get_field(name))
        local target=assert(target_menu:get_field(name))
        assert(source:get_type_definition()==target:get_type_definition() and source:get_size()==target:get_size())
        copy:call(nil,source,0,target,0,source:get_size())
    end
    journal.initialized_bytes_identical=encoded(initialized)==dump.base64
    control.write("restore-test-journal",journal)
    assert(journal.initialized_bytes_identical,"Initialized copy changed serialized character data")
    restored=initialized
    local before={}
    for i=0,slots:get_size()-1 do before[i]=slots:get_element(i) end
    local replacement=records.array(slots,slots:get_size())
    replacement[request.target_index]=restored
    journal.stage="attaching"; journal.boot=boot
    control.write("restore-test-journal",journal)
    root:set_field("_Data",replacement)
    assert(root:get_field("_Data"):get_element(2)==restored)
    assert(root:get_field("_Data"):get_element(0)==before[0] and root:get_field("_Data"):get_element(1)==before[1])
    journal.stage="attached"; journal.byte_count=dump.byte_count
    journal.name=restored:get_field("_BasicData"):get_field("CharName")
    journal.prior_name=before[2]:get_field("_BasicData"):get_field("CharName")
    journal.target_index=2; journal.source_bytes_identical=true
    control.write("restore-test-journal",journal)
end
local callback=assert(sdk.find_type_definition("ace.SaveDataManagerBase.cSaveRequest"):get_method("execCallback"))
sdk.hook(callback,function(args)
    local ok,err=pcall(function()
        local r=sdk.to_managed_object(args[2])
        if not r or r:get_type_definition():get_full_name()~="ace.SaveDataManagerBase.cSaveRequest" then return end
        local target=r:call("get_Target")
        if not target or target:get_type_definition():get_full_name()~="app.savedata.cUserSaveData" then return end
        report.save_completions[#report.save_completions+1]={result=sdk.to_int64(args[3]),error=sdk.to_int64(args[4]),utc=os.date("!%Y-%m-%dT%H:%M:%SZ")}
        emit()
    end)
    if not ok then report.hook_error=tostring(err) end
end,function(retval) return retval end)
local last=0
re.on_application_entry("UpdateBehavior",function()
    if os.clock()-last<1 then return end
    last=os.clock()
    local ok,err=pcall(function()
        local manager,root,slots,state=records.context()
        report.state=state and state:get_type_definition():get_full_name()
        report.current=manager and manager:get_field("CurrentUserDataIndex")
        if manager and report.current and report.current>=0 and slots and report.current<slots:get_size() then
            local selected=manager:call("getCurrentUserSaveData")
            local basic=selected and selected:get_field("_BasicData")
            report.selected_name=basic and basic:get_field("CharName")
        end
        report.busy=manager and records.busy(manager)
        report.journal_stage=journal.stage
        report.names={}
        if slots then
            for i=0,slots:get_size()-1 do
                local record=slots:get_element(i)
                local basic=record and record:get_field("_BasicData")
                report.names[#report.names+1]=basic and basic:get_field("CharName") or ""
            end
        end
        if not report.observe_only and journal.stage=="pending" and report.state=="app.TitleState" and not report.busy then
            local guis=sdk.get_managed_singleton("app.GUIManager"):get_field("_AllGUI")
            for i=0,guis:get_size()-1 do
                local g=guis:get_element(i)
                if g and g:get_type_definition():get_full_name()=="app.GUI010102" and g:get_field("_BaseState")==2 then
                    assert(slots:get_size()==3,"Expected a native three-character copy")
                    journal.stage="restoring";control.write("restore-test-journal",journal)
                    restore(root,slots); break
                end
            end
        end
        emit()
    end)
    if not ok then
        report.error=tostring(err)
        if journal.stage=="restoring" or journal.stage=="initializing" or journal.stage=="attaching" then
            journal.stage="failed";journal.error=tostring(err);control.write("restore-test-journal",journal)
        end
        emit()
    end
end)
