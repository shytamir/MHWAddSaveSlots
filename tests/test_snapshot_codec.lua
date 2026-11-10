-- Mocked regression for the observed raw-object load failure and menu loss.
-- This tests refusal/ownership guarantees, not engine serialization coverage.
package.path="reframework/autorun/?.lua;"..package.path
local checks=0
local function check(value,message) checks=checks+1;assert(value,message) end
local function rejects(fn,fragment)
    local ok,err=pcall(fn)
    check(not ok and tostring(err):find(fragment,1,true),"Expected rejection: "..fragment)
end
local mode,raw,last_created
local serialize_calls,base64_calls=0,0
local types={}
local function td(name)
    if not types[name] then
        types[name]={get_full_name=function()return name end,get_runtime_type=function(self)return self end}
    end
    return types[name]
end
local function object(name,fields)
    local value={fields=fields or {},kind=td(name)}
    function value:get_type_definition()return self.kind end
    function value:get_field(key)return self.fields[key]end
    function value:add_ref()end
    return value
end
local function array(values,kind)
    local value=object(kind or "System.Byte[]")
    value.size=#values
    for i=1,#values do value[i-1]=values[i]end
    function value:get_size()return self.size end
    function value:get_element(i)return self[i]end
    return value
end
local function character(payload,recent,favorite)
    local value=object("app.savedata.cUserSaveParam",{
        Active=1,_BasicData=object("Basic",{CharName="Fixture"}),
        _StartMenu=object("Menu",{RecentMenu=array({recent},"MenuId[]"),FavoriteMenu=array({favorite},"MenuId[]")})})
    value.payload=payload
    return value
end
local function method(fn)return {call=function(_,_,...)return fn(...)end}end
local create=method(function()
    if mode=="factory failure" then return nil end
    local value=character(0,0,0)
    last_created=value
    function value:call(name,source)
        if name=="init" then
            self.ready=true
            self.initial_recent=self.fields._StartMenu.fields.RecentMenu
            self.initial_favorite=self.fields._StartMenu.fields.FavoriteMenu
            if mode=="layout changed" then self.initial_recent.size=2 end
        elseif name=="copyFrom(ace.cSaveDataBase)" then
            assert(self.ready,"copy before init")
            if mode=="copy rejected" then return false end
            self.payload=mode=="copy lost data" and 2 or source.payload
            -- Reproduce the observed engine omission: menu arrays remain zero.
            return true
        else error("Unexpected call: "..name)end
    end
    return value
end)
local serialize=method(function(_,record)
    serialize_calls=serialize_calls+1
    return array({record.payload,record.fields._StartMenu.fields.RecentMenu[0],record.fields._StartMenu.fields.FavoriteMenu[0]})
end)
local deserialize=method(function()
    raw=character(mode=="raw mismatch" and 2 or 1,2,3)
    if mode=="wrong type" then raw.kind=td("Other")end
    return raw
end)
local encodings={AQID={1,2,3},AgID={2,2,3},AQAA={1,0,0}}
local encode=method(function(bytes)
    base64_calls=base64_calls+1
    for encoded,values in pairs(encodings)do
        if bytes:get_size()==#values and bytes[0]==values[1] and bytes[1]==values[2] and bytes[2]==values[3]then return encoded end
    end
    error("Unknown fixture encoding")
end)
local decode=method(function(encoded)return array(assert(encodings[encoded]))end)
local copy=method(function(source,first,target,offset,count)
    for i=0,count-1 do target[offset+i]=source[first+i]end
end)
local function typesMethod(name)
    local value=td(name)
    function value:get_method(key)
        if name=="app.savedata.cUserSaveParam" and key=="create"then return create end
        if key=="serializeMessagePackInternal"then return serialize end
        if key=="deserializeMessagePackInternal"then return deserialize end
        if key=="ToBase64String(System.Byte[])"then return encode end
        if key=="FromBase64String(System.String)"then return decode end
        if key:find("Copy(",1,true)==1 then return copy end
        error("Unexpected method: "..key)
    end
    function value:get_field(key)assert(key=="None");return {get_data=function()return 0 end}end
    return value
end
sdk={find_type_definition=typesMethod,create_managed_array=function(_,count)
    local values={};for i=1,count do values[i]=0 end;return array(values)
end}
local codec=require("MHWAddSaveSlots.snapshot_codec")
local entry={bytes=3,data="AQID"}
local result=codec.decode(entry)
check(result==last_created and result~=raw and result.ready,"Return an initialized native object, never raw deserialization")
check(codec.encode(result).data==entry.data,"Preserve every serialized byte after initialization")
local menu=result:get_field("_StartMenu")
check(menu:get_field("RecentMenu")==result.initial_recent and menu:get_field("FavoriteMenu")==result.initial_favorite,
    "Retain the initialized menu arrays")
check(menu:get_field("RecentMenu")~=raw:get_field("_StartMenu"):get_field("RecentMenu"),"Do not share reconstructed arrays")
for _,case in ipairs({
    {"factory failure","Character factory failed"},{"copy rejected","Game rejected reconstructed character"},
    {"layout changed","Character menu array layout changed"},{"copy lost data","Initialized character differs from snapshot"},
    {"raw mismatch","Reconstructed character does not round-trip"},{"wrong type","Unexpected reconstructed type"}
})do mode=case[1];rejects(function()codec.decode(entry)end,case[2])end
mode=nil
rejects(function()codec.decode({bytes=4,data="AQID"})end,"Invalid snapshot encoding length")
rejects(function()codec.decode({bytes=3,data="!!!!"})end,"Invalid snapshot encoding")
local jobs=require("MHWAddSaveSlots.jobs")
local before_serialize,before_base64=serialize_calls,base64_calls
local task=jobs.new(function(yield)return codec.encode(result,yield)end)
task:step()
check(serialize_calls==before_serialize+1 and base64_calls==before_base64 and not task.done,"Serialization and Base64 ran in the same update")
task:step()
check(base64_calls==before_base64+1 and not task.done,"Base64 did not yield before further work")
task:step()
check(task.done and not task.error and task.result.data==entry.data,"Incremental codec changed snapshot bytes")
print("Snapshot codec: "..checks.." assertions passed")
