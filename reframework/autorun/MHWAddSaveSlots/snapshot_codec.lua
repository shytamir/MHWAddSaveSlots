-- Engine-owned character serialization. No native file format or offsets.
local M={MAX_BYTES=64*1024*1024}
local records=require("MHWAddSaveSlots.records")
local api
local function methods()
    if api then return api end
    local serializer=assert(sdk.find_type_definition("via.Serializer"),"Engine serializer unavailable")
    local convert=assert(sdk.find_type_definition("System.Convert"))
    local td=assert(sdk.find_type_definition("app.savedata.cUserSaveParam"))
    api={td=td,runtime=assert(td:get_runtime_type()),
        serialize=assert(serializer:get_method("serializeMessagePackInternal")),
        deserialize=assert(serializer:get_method("deserializeMessagePackInternal")),
        encode=assert(convert:get_method("ToBase64String(System.Byte[])")),
        decode=assert(convert:get_method("FromBase64String(System.String)")),
        copy=assert(sdk.find_type_definition("System.Array"):get_method(
            "Copy(System.Array, System.Int32, System.Array, System.Int32, System.Int32)"))}
    assert(sdk.find_type_definition("via.Serializer.Options"):get_field("None"):get_data(nil)==0)
    return api
end
function M.validate(entry,checkpoint)
    assert(type(entry)=="table" and type(entry.bytes)=="number" and entry.bytes%1==0 and
        entry.bytes>0 and entry.bytes<=M.MAX_BYTES,"Invalid snapshot byte count")
    assert(type(entry.data)=="string" and #entry.data==4*math.ceil(entry.bytes/3),"Invalid snapshot encoding length")
    if checkpoint then
        for first=1,#entry.data,16384 do
            assert(not entry.data:sub(first,first+16383):find("[^A-Za-z0-9+/=]"),"Invalid snapshot encoding")
            checkpoint("validate")
        end
    else
        assert(not entry.data:find("[^A-Za-z0-9+/=]"),"Invalid snapshot encoding")
    end
    return entry
end
function M.encode(record,checkpoint)
    local a=methods()
    assert(record:get_type_definition():get_full_name()==a.td:get_full_name(),"Unexpected character type")
    local bytes=assert(a.serialize:call(nil,a.runtime,record,0),"Character serialization failed")
    bytes:add_ref()
    if checkpoint then checkpoint("engine serialize",true) end
    local basic=record:get_field("_BasicData")
    local entry={bytes=bytes:get_size(),data=a.encode:call(nil,bytes),
        name=basic and basic:get_field("CharName") or "",active=record:get_field("Active")~=0}
    if checkpoint then
        checkpoint("engine Base64",true)
        -- The archive validates this entry before publishing it. Avoid scanning
        -- the same native-generated Base64 both here and again in capture.
        return entry
    end
    return M.validate(entry)
end
function M.decode(entry)
    M.validate(entry)
    local a=methods()
    local bytes=assert(sdk.create_managed_array("System.Byte",entry.bytes)); bytes:add_ref()
    local offset=0
    for first=1,#entry.data,4096 do
        local part=assert(a.decode:call(nil,entry.data:sub(first,first+4095)),"Snapshot decoding failed")
        part:add_ref()
        local count=part:get_size()
        assert(count>0 and offset+count<=entry.bytes,"Snapshot chunk exceeds expected length")
        a.copy:call(nil,part,0,bytes,offset,count)
        offset=offset+count
    end
    assert(offset==entry.bytes and a.encode:call(nil,bytes)==entry.data,"Decoded snapshot differs")
    local record=assert(a.deserialize:call(nil,a.runtime,bytes,0),"Character reconstruction failed")
    record:add_ref()
    assert(record:get_type_definition():get_full_name()==a.td:get_full_name(),"Unexpected reconstructed type")
    assert(M.encode(record).data==entry.data,"Reconstructed character does not round-trip")
    -- Raw deserialization reproduced the bytes but crashed on live loading.
    -- The native factory/init/copy path also supplies runtime-only state.
    local initialized=records.new()
    assert(initialized:call("copyFrom(ace.cSaveDataBase)",record)==true,"Game rejected reconstructed character")
    -- copyFrom omits these serialized menu arrays on the tested Wilds build.
    -- Copy contents into the initialized arrays, retaining their ownership.
    local source_menu=assert(record:get_field("_StartMenu"),"Snapshot menu data missing")
    local target_menu=assert(initialized:get_field("_StartMenu"),"Initialized menu data missing")
    for _,name in ipairs({"RecentMenu","FavoriteMenu"}) do
        local source=assert(source_menu:get_field(name),"Snapshot menu array missing")
        local target=assert(target_menu:get_field(name),"Initialized menu array missing")
        assert(source:get_type_definition()==target:get_type_definition() and source:get_size()==target:get_size(),
            "Character menu array layout changed")
        a.copy:call(nil,source,0,target,0,source:get_size())
    end
    -- Fail before attachment if any serialized field was lost or changed.
    assert(M.encode(initialized).data==entry.data,"Initialized character differs from snapshot")
    return initialized
end
return M
