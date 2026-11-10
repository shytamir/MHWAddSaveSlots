-- Detached diagnosis only: compare the engine's initialized copy with raw
-- reconstruction. No attachment, selection change, or native save request.
local done=false
re.on_application_entry("UpdateBehavior",function()
    if done then return end
    done=true
    local report={stage="starting",differences={}}
    local function emit() json.dump_file("MHWAddSaveSlots.restore-initialization.json",report) end
    local ok,err=pcall(function()
        local control=require("MHWAddSaveSlots.control")
        assert(control.enabled(control.read("session")))
        local request=control.read("restore-test-request")
        local dump=assert(json.load_file(request.snapshot))
        local serializer=assert(sdk.find_type_definition("via.Serializer"))
        local convert=assert(sdk.find_type_definition("System.Convert"))
        local encode=assert(convert:get_method("ToBase64String(System.Byte[])"))
        local decode=assert(convert:get_method("FromBase64String(System.String)"))
        local serialize=assert(serializer:get_method("serializeMessagePackInternal"))
        local deserialize=assert(serializer:get_method("deserializeMessagePackInternal"))
        local td=assert(sdk.find_type_definition("app.savedata.cUserSaveParam"))
        local bytes=assert(sdk.create_managed_array("System.Byte",dump.byte_count));bytes:add_ref()
        local copy=assert(sdk.find_type_definition("System.Array"):get_method("Copy(System.Array, System.Int32, System.Array, System.Int32, System.Int32)"))
        local offset=0
        for first=1,#dump.base64,4096 do
            local part=assert(decode:call(nil,dump.base64:sub(first,first+4095)));part:add_ref()
            copy:call(nil,part,0,bytes,offset,part:get_size());offset=offset+part:get_size()
        end
        assert(offset==dump.byte_count and encode:call(nil,bytes)==dump.base64)
        local raw=assert(deserialize:call(nil,td:get_runtime_type(),bytes,0));raw:add_ref()
        local initialized=require("MHWAddSaveSlots.records").new()
        assert(initialized:call("copyFrom(ace.cSaveDataBase)",raw)==true)
        local function encoded(value,t)
            local b=assert(serialize:call(nil,t:get_runtime_type(),value,0));b:add_ref()
            return encode:call(nil,b),b:get_size()
        end
        local after,count=encoded(initialized,td)
        report.initialized_bytes=count
        json.dump_file("MHWAddSaveSlots.initialized-character.json",{base64=after,byte_count=count})
        report.stage="comparing fields";emit()
        report.start_menu_fields={}
        local sa,sb=raw:get_field("_StartMenu"),initialized:get_field("_StartMenu")
        for _,f in ipairs(sa:get_type_definition():get_fields()) do
            if not f:is_static() then
                report.start_menu_fields[#report.start_menu_fields+1]={name=f:get_name(),type=f:get_type():get_full_name(),raw=tostring(f:get_data(sa)),initialized=tostring(f:get_data(sb))}
            end
        end
        local t=td
        while t do
            for _,f in ipairs(t:get_fields()) do
                if not f:is_static() then
                    report.current_field=f:get_name();emit()
                    local fieldok,fielderr=pcall(function()
                    local a,b=f:get_data(raw),f:get_data(initialized)
                    if type(a)=="userdata" and type(b)=="userdata" then
                        local aa,al=encoded(a,f:get_type());local bb,bl=encoded(b,f:get_type())
                        if aa~=bb then report.differences[#report.differences+1]={field=f:get_name(),type=f:get_type():get_full_name(),raw_bytes=al,initialized_bytes=bl} end
                    elseif a~=b then report.differences[#report.differences+1]={field=f:get_name(),raw=tostring(a),initialized=tostring(b)} end
                    end)
                    if not fieldok then report.differences[#report.differences+1]={field=f:get_name(),comparison_error=tostring(fielderr)} end
                end
            end
            t=t:get_parent_type()
        end
        -- Do not call setupAfterLoad here. It threw on a detached raw object
        -- during investigation; byte reconstruction does not initialize it.
        report.stage="complete"
    end)
    if not ok then report.error=tostring(err);report.failed_at=report.stage;report.stage="failed" end
    emit()
end)
