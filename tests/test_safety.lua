-- Run with Lua 5.3+ (or Fengari). These are mocked API/transaction tests, not
-- evidence about Wilds' serializer or its fresh-character editor.
package.path="reframework/autorun/?.lua;"..package.path
local policy=require("MHWAddSaveSlots.policy")
local assertions=0
local function check(value, message) assertions=assertions+1; assert(value,message) end
local function rejects(fn) check(not pcall(fn),"Expected rejection") end
for _,index in ipairs({-1,3,4,15,255}) do check(policy.native_index(index,2)==2) end
for i=0,2 do check(policy.native_index(i,1)==i) end
rejects(function() policy.count(17) end)
rejects(function() policy.count(4.5) end)
local now=1000
local files={session={isolated=true,mutation_enabled=true,session_id="test",expires_utc="2099-01-01T00:00:00Z"}}
files.companion={session_id="test",heartbeat=now,ready=true,slots=5,snapshot="backup5",ack=""}
local function copy(value)
    if type(value)~="table" then return value end
    local out={};for k,v in pairs(value) do out[k]=copy(v) end;return out
end
local control={read=function(n) return files[n] or {} end,write=function(n,v) files[n]=copy(v) end,
    enabled=function(s) return s.isolated and s.mutation_enabled end}
package.loaded["MHWAddSaveSlots.control"]=control
local hooks,storage={},{}
thread={get_hook_storage=function() return storage[#storage] end}
log={error=function() end}
os.time=function() return now end
os.clock=function() return now end
local function object(kind,fields)
    local obj={fields=fields or {},kind=kind}
    function obj:get_field(name) return self.fields[name] end
    function obj:set_field(name,v) self.fields[name]=v end
    function obj:add_ref() end
    function obj:get_address() return tostring(self) end
    function obj:get_type_definition() return {get_full_name=function() return self.kind end} end
    return obj
end
local serial=0
local function record()
    serial=serial+1
    local obj=object("app.savedata.cUserSaveParam",{Active=0,_BasicData=object("Basic",{CharName="",OtomoName=""}),identity=serial})
    function obj:call(name,source)
        if name=="init" then self.fields.Active=0; return end
        if name=="copyFrom(ace.cSaveDataBase)" then self.fields.Active=source.fields.Active; self.fields.copied=true; return true end
    end
    return obj
end
local function array(n)
    local arr={size=n}
    function arr:add_ref() end
    function arr:get_size() return self.size end
    function arr:get_element(i) return self[i] end
    for i=0,n-1 do arr[i]=record() end
    return arr
end
local root=object("app.savedata.cUserSaveData",{_Data=array(5)})
for i=0,4 do root.fields._Data[i].fields.Active=1 end
local common=object("app.savedata.cSystemCommonParam",{LastUserIndex=4})
local manager=object("app.SaveDataManager",{_UserSaveData=root,CurrentUserDataIndex=4,
    _SystemSaveData=object("System",{_Data=object("Param",{_SystemCommon=common})})})
local busy=false
function manager:call(name)
    if name=="get_IsSaveRunning" or name=="get_IsSaveLoadFlowRunning" then return busy end
    if name=="getCurrentUserSaveData" then return root.fields._Data[self.fields.CurrentUserDataIndex] end
    if name=="requestSaveDataManualSave" then return end
end
local flow=object("app.GameFlowManager",{_CurrentGameState=object("app.IngameState")})
sdk={PreHookResult={SKIP_ORIGINAL="skip"},to_ptr=function(v) return v end,to_managed_object=function(v) return v end,
    to_int64=function(v) return v==true and 1 or v==false and 0 or v end,
    get_managed_singleton=function(n) return n=="app.SaveDataManager" and manager or n=="app.GameFlowManager" and flow or nil end,
    create_managed_array=function(_,n) return array(n) end,create_managed_string=function(v) return v end,
    hook=function(m,pre,post) hooks[m]={pre=pre,post=post} end}
function sdk.find_type_definition(name)
    return {get_method=function(_,method)
        if method=="create" then return {call=function() return record() end} end
        return name..":"..method
    end,get_fields=function()
        return {{is_static=function() return true end,
            get_name=function() return name:find("EXECUTE_RESULT") and "SUCCESS" or "NONE" end,
            get_data=function() return name:find("EXECUTE_RESULT") and 7 or 11 end},
            {is_static=function() return true end,get_name=function() return "UNKNOWN" end,get_data=function() return 99 end}}
    end}
end
local function call(key,args,result,original)
    storage[#storage+1]={}
    local h=assert(hooks[key],key)
    local skipped=h.pre(args)=="skip"
    if not skipped and original then original() end
    local value=h.post(result)
    table.remove(storage)
    return value,skipped
end
local records=require("MHWAddSaveSlots.records")
local safety=require("MHWAddSaveSlots.compat")
local normal_call=manager.call
local load_resumed=false
function manager:call(name,...)
    if name=="systemRequestUserLoad" then
        return call("app.SaveDataManager:systemRequestUserLoad",{nil,self,nil},nil,function() load_resumed=true end)
    end
    return normal_call(self,name,...)
end
files.companion.ready=false
call("app.SaveDataManager:systemRequestUserLoad",{nil,manager,nil},nil)
check(not load_resumed and select(4,safety.state())==nil,"Temporary backup wait became a permanent load fault")
files.companion.ready=true
now=now+1;files.companion.heartbeat=now;safety.update()
check(load_resumed,"Deferred native load did not resume after backup verification")
local native0=root.fields._Data[0]
call("app.savedata.cSystemCommonParam:runSaveDataCore",{nil,common},true,function() check(common.fields.LastUserIndex==0) end)
check(manager.fields.CurrentUserDataIndex==4,"Persistence guard changed live selection")
local staging=object("app.savedata.cUserSaveData",{_Data=array(3)})
local staging0=staging.fields._Data[0]
call("app.savedata.cUserSaveData:copyFrom(ace.cSaveDataBase)",{nil,staging,root},true)
check(staging.fields._Data.size==5 and staging.fields._Data[0]==staging0,"Native staging entries changed")
local large=object("app.savedata.cUserSaveData",{_Data=array(16)})
call("app.savedata.cUserSaveData:copyFrom(ace.cSaveDataBase)",{nil,staging,large},true)
check(staging.fields._Data.size==16)
local fresh=records.new()
check(fresh.fields.Active==0 and not fresh.fields.copied,"Fresh record used cloning")
local current_request
local function make_request(target,kind)
    local req=object(kind or "ace.SaveDataManagerBase.cSaveRequest",{Target=target})
    function req:call() return self.fields.Target end
    return req
end
local function request(target)
    local req=make_request(target)
    local result=call("ace.SaveDataManagerBase.cSaveRequest:execMainFunction",{nil,req},11)
    if result==11 then current_request=req end
    return result==11
end
local function complete(target,success)
    check(current_request.fields.Target==target)
    call("ace.SaveDataManagerBase.cSaveRequest:execCallback",{nil,current_request,success and 7 or 99,11},nil)
end
local function tick() now=now+1; files.companion.heartbeat=now; safety.update() end
call("ace.SaveDataManagerBase.cSaveRequest:execCallback",{nil,make_request(root,"ace.SaveDataManagerBase.cLoadRequest"),7,11},nil)
check(select(4,safety.state())==nil,"Load callback was mistaken for save completion")
check(request(root)==true) -- Direct execution: no requestSave convenience call.
check(request(root)==false,"Second save was not held for backup")
complete(root,true)
check(files["save-start-"..files.runtime.event.id].event.phase=="writing","Start receipt was overwritten")
check(files["save-end-"..files.runtime.event.id].event.phase=="completed","Completion receipt was not persisted")
check(request(root)==false,"Unacknowledged completed save allowed overwrite")
local function acknowledge(slots,snapshot)
    files.companion.ack=files.runtime.event.id
    files.companion.slots=slots;files.companion.snapshot=snapshot
end
acknowledge(5,"expanded-new")
manager.fields.CurrentUserDataIndex=1
safety.prepare_trim()
tick()
check(files.runtime.trim.stage=="backing-up","Old backup incorrectly completed new trim preparation")
check(request(root)==true); complete(root,true); acknowledge(5,"expanded-trim")
tick(); check(files.runtime.trim.stage=="ready")
safety.confirm_trim(); tick()
check(root.fields._Data.size==5,"Shrank before durable intent acknowledgement")
files.companion.trim_ack=files.runtime.trim.id
tick(); check(root.fields._Data.size==3 and root.fields._Data[0]==native0,"Trim changed native identity")
check(request(root)==true); complete(root,true); acknowledge(3,"trimmed")
tick(); check(files.runtime.trim.stage=="complete")
check(common.fields.LastUserIndex<=2 and manager.fields.CurrentUserDataIndex==1)
call("app.savedata.cUserSaveData:copyFrom(ace.cSaveDataBase)",{nil,staging,root},true)
check(staging.fields._Data.size==3,"Post-trim Save and Quit staging could not shrink")
files.companion.heartbeat=now-20
check(request(root)==false,"Stale companion allowed a save")
files.companion.heartbeat=now
files.companion.session_id="other"
now=now+20 -- previously validated heartbeat expires; another session cannot renew it
check(request(root)==false,"Different session authorized a save")
local latest={slots=5,snapshot="current",ack="ok"}
rejects(function() policy.can_save(3,latest,nil,"runtime",nil) end)
rejects(function() policy.can_save(3,latest,nil,"runtime",{stage="prepared",runtime_id="runtime",source="old",id="trim"}) end)
-- Exercise the selector's fresh append path, including native editor routing.
files.companion={session_id="test",heartbeat=now,ready=true,slots=3,snapshot="trimmed",ack=files.runtime.event.id}
flow.fields._CurrentGameState=object("app.TitleState")
local list={selected=-1,call=function(self,name,value)
    if name=="set_ItemCount" then self.count=value end
    if name=="set_SelectedIndex" then self.selected=value end
    if name=="get_SelectedIndex" then return self.selected end
end}
local selected=false
local gui=object("app.GUI010102",{_BaseState=2,_DataList=list})
function gui:call(name) if name=="selectFinish" then selected=true end end
local guis=array(1); guis[0]=gui
local gui_manager=object("app.GUIManager",{_AllGUI=guis})
local previous_singleton=sdk.get_managed_singleton
sdk.get_managed_singleton=function(name) return name=="app.GUIManager" and gui_manager or previous_singleton(name) end
re={on_frame=function() end}
imgui={load_font=function() return nil end}
local selector=require("MHWAddSaveSlots.poc")
selector.configure(require("MHWAddSaveSlots.compat"))
local native_before={root.fields._Data[0],root.fields._Data[1],root.fields._Data[2]}
files.command={session_id="test",id="new-empty",action="append_fresh"}
now=now+1;selector.update()
check(files.result.ok and root.fields._Data.size==4)
check(root.fields._Data[3].fields.Active==0 and not root.fields._Data[3].fields.copied)
for i=0,2 do check(root.fields._Data[i]==native_before[i+1]) end
files.command={session_id="test",id="new-editor",action="create_new",index=3}
now=now+1;selector.update()
check(files.result.ok and selected and list.selected==3 and manager.fields.CurrentUserDataIndex==3)
-- Syntax-check every shipped module, including modules not exercised above.
for _,name in ipairs({"control","policy","records","compat","poc","probe"}) do
    check(loadfile("reframework/autorun/MHWAddSaveSlots/"..name..".lua")~=nil,"Syntax: "..name)
end
check(loadfile("reframework/autorun/MHWAddSaveSlots.lua")~=nil)
print("PASS: "..assertions.." Lua policy, mocked-hook, fresh initializer, capacity, backup gate, and trim assertions")
