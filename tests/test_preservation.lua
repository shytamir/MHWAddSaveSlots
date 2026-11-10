-- Mocked hook/transaction tests for the Lua archive backend; not game evidence.
package.path="reframework/autorun/?.lua;"..package.path
local checks=0
local function check(v,m) checks=checks+1;assert(v,m) end
local function rejects(fn)check(not pcall(fn),"Expected rejection")end
local function clone(v)if type(v)~="table" then return v end local x={} for k,a in pairs(v)do x[k]=clone(a)end return x end
local now=1000
os.time=function()return math.floor(now) end;os.clock=function()return now end
local files={session={isolated=true,mutation_enabled=true,session_id="fixture",expires_utc="2099-01-01T00:00:00Z"}}
local control={read=function(n)return files[n] or {} end,write=function(n,v)files[n]=clone(v)end,
    enabled=function(s)return s.isolated==true and s.mutation_enabled==true end}
package.loaded["MHWAddSaveSlots.control"]=control
local disk,write_failure={},nil
local backend={exists=function(p)return disk[p]~=nil end,
    read=function(p)assert(disk[p]);return clone(disk[p])end,
    write=function(p,v)assert(not disk[p]);assert(not write_failure or not p:find(write_failure,1,true),"Disk full");disk[p]=clone(v)end,
    list=function(prefix)local out={} for p in pairs(disk)do if p:sub(1,#prefix)==prefix then out[#out+1]=p end end return out end}
local real_archive=require("MHWAddSaveSlots.archive")
local store=real_archive.open("test",backend)
package.loaded["MHWAddSaveSlots.archive"]={open=function()return store end}
local hooks,storage={},{}
thread={get_hook_storage=function()return storage[#storage]end}
log={error=function()end}
local function object(kind,fields)
    local o={kind=kind,fields=fields or {}}
    function o:get_field(n)return self.fields[n]end
    function o:set_field(n,v)self.fields[n]=v end
    function o:add_ref()end
    function o:get_address()return tostring(self)end
    function o:get_type_definition()return {get_full_name=function()return self.kind end,get_fields=function()return {}end,get_parent_type=function()end,is_array=function()return false end}end
    return o
end
local function record(name)
    local r=object("app.savedata.cUserSaveParam",{Active=1,_BasicData=object("Basic",{CharName=name,OtomoName="Cat"})})
    function r:call(n)if n=="init" then self.fields.Active=0 end end
    return r
end
local function array(n)
    local a={size=n};function a:get_size()return self.size end;function a:get_element(i)return self[i]end;function a:add_ref()end
    for i=0,n-1 do a[i]=record("Hunter "..i)end return a
end
local root=object("app.savedata.cUserSaveData",{_Data=array(5)})
local common=object("app.savedata.cSystemCommonParam",{LastUserIndex=4})
local manager=object("app.SaveDataManager",{_UserSaveData=root,CurrentUserDataIndex=4,
    _SystemSaveData=object("System",{_Data=object("Param",{_SystemCommon=common})})})
local busy=false
local manual=0
function manager:call(name)
    if name=="get_IsSaveRunning" or name=="get_IsSaveLoadFlowRunning"then return busy end
    if name=="requestSaveDataManualSave"then manual=manual+1 end
    if name=="getCurrentUserSaveData"then return root.fields._Data[self.fields.CurrentUserDataIndex]end
end
local flow=object("app.GameFlowManager",{_CurrentGameState=object("app.IngameState")})
sdk={PreHookResult={SKIP_ORIGINAL="skip"},to_ptr=function(v)return v end,to_managed_object=function(v)return v end,to_int64=function(v)return v end,
    get_managed_singleton=function(n)return n=="app.SaveDataManager" and manager or n=="app.GameFlowManager" and flow or nil end,
    create_managed_array=function(_,n)return array(n)end,
    hook=function(m,pre,post)hooks[m]={pre=pre,post=post}end,
    find_type_definition=function(name)return {
        get_method=function(_,method)
            if method=="create" then return {call=function()return record("")end} end
            return name..":"..method
        end,
        get_fields=function()return {
            {is_static=function()return true end,get_name=function()return name:find("EXECUTE_RESULT") and "SUCCESS" or "NONE"end,
                get_data=function()return name:find("EXECUTE_RESULT") and 7 or 11 end},
            {is_static=function()return true end,get_name=function()return "UNKNOWN"end,get_data=function()return 99 end}}
        end}
    end}
io.open=function()return nil end
local codec_failure=false
local encodes=0
package.loaded["MHWAddSaveSlots.snapshot_codec"]={
    encode=function(r)encodes=encodes+1;assert(not codec_failure,"Serialization failed");return {bytes=3,data="AQID",name=r:get_field("_BasicData"):get_field("CharName"),active=true}end,
    decode=function(e)return record(e.name)end}
local initial={};for i=0,4 do initial[#initial+1]=package.loaded["MHWAddSaveSlots.snapshot_codec"].encode(root.fields._Data[i])end
local base=store:capture(initial,"baseline");store:commit(base.id)
local safety=require("MHWAddSaveSlots.preservation")
local function call(key,args,result,original)
    storage[#storage+1]={};local h=assert(hooks[key],key)
    local skipped=h.pre(args)=="skip";if not skipped and original then original()end;local returned=h.post(result)
    storage[#storage]=nil;return skipped,returned
end
local exec="ace.SaveDataManagerBase.cSaveRequest:execMainFunction"
local callback="ace.SaveDataManagerBase.cSaveRequest:execCallback"
local request=object("ace.SaveDataManagerBase.cSaveRequest")
function request:call(n)if n=="get_Target"then return root end end
local function finish_backup()
    for _=1,80 do now=now+0.02;safety.update() end
end
local function save(wait)
    local before=encodes
    local skipped=call(exec,{nil,request},11);check(not skipped,"Unexpected save refusal")
    call(callback,{nil,request,7,11},0)
    check(encodes==before,"Native save hook serialized characters")
    if wait~=false then finish_backup() end
end
safety.clamp(common)
check(common.fields.LastUserIndex==0 and manager.fields.CurrentUserDataIndex==4,"Persisted index must not change live selection")
save(false)
local status,event=safety.state()
check(event.phase=="completed" and status.ack~=event.id and store.committed.id==base.id,"Native success must precede backup verification")
check(real_archive.open("test",backend):capacity()==5,"Crash before backup must preserve native capacity")
finish_backup()
check(event.phase=="completed" and status.ack==event.id and store.committed.slots==5,status.backup_warning or "Background save backup did not finish")
local expanded=store.committed.id
flow.fields._CurrentGameState=object("app.TitleState")
local native_source=object("app.savedata.cUserSaveData",{_Data=array(3)})
local copy_skipped=call("app.savedata.cUserSaveData:copyFrom(ace.cSaveDataBase)",{nil,root,native_source},1,function()
    for i=0,2 do root.fields._Data[i]=native_source.fields._Data[i] end
end)
check(not copy_skipped and root.fields._Data:get_size()==5,"Smaller native load must retain reserved extra capacity")
check(root.fields._Data[0]==native_source.fields._Data[0] and root.fields._Data[3].fields.Active==0,"Native loaded records must survive; missing extras stay empty")
check(store:load(expanded).slots==5,"Smaller native load must retain expanded recovery data")
flow.fields._CurrentGameState=object("app.IngameState")
codec_failure=true
local skipped,retval=call(exec,{nil,request},11)
check(not skipped and retval==11,"Backup serialization must not block native write")
call(callback,{nil,request,7,11},0)
finish_backup()
check(safety.state().backup_warning~=nil and store.committed.id==expanded,"Serialization failure must retain last verified backup")
codec_failure=false
save()
manager.fields.CurrentUserDataIndex=0
safety.prepare_trim();check(manual==1)
save();now=now+1;safety.update()
local _,_,trim=safety.state();check(trim.stage=="ready")
safety.confirm_trim();now=now+1;safety.update()
check(root.fields._Data:get_size()==3 and manual==2)
save();now=now+1;safety.update()
check(trim.stage=="complete" and store:capacity()==3)
check(store:load(expanded).slots==5,"Expanded archive lost after trim")
flow.fields._CurrentGameState=object("app.TitleState")
local native0,native1,native2=root.fields._Data[0],root.fields._Data[1],root.fields._Data[2]
check(safety.restore_character(expanded,4)==3)
check(root.fields._Data:get_size()==4 and root.fields._Data[0]==native0 and root.fields._Data[1]==native1 and root.fields._Data[2]==native2)
save()
-- Autosaves can supersede pending work without waiting for an older backup.
local catalog_before=#store.catalog
local keep=store.committed.id
save(false)
local first_pending=select(2,safety.state()).id
save(false)
local newest=select(2,safety.state()).id
check(newest~=first_pending and store.committed.id==keep,"New native save waited on/replaced the prior verified archive")
finish_backup()
check(#store.catalog==catalog_before+1 and safety.state().ack==newest,"Superseded queued backup was published")
-- A staging copy can be reused before execMainFunction; cancel the in-flight
-- capture at copyFrom so an old generation cannot publish mixed records.
catalog_before=#store.catalog;keep=store.committed.id
save(false)
now=now+0.02;safety.update() -- create worker
now=now+0.02;safety.update() -- capture one character
local reused=object("app.savedata.cUserSaveData",{_Data=array(4)})
call("app.savedata.cUserSaveData:copyFrom(ace.cSaveDataBase)",{nil,root,reused},1)
finish_backup()
check(store.committed.id==keep and #store.catalog==catalog_before,"Reused staging object published an obsolete backup")
save()
check(#store.catalog==catalog_before+1,"Replacement native save could not produce a verified backup")
-- Once all records are immutable strings, finish their write/verification even
-- if a new autosave arrives. Otherwise a busy autosave stream could starve all
-- backups. Completion of the older backup must not acknowledge the newer save.
catalog_before=#store.catalog
save(false)
local frozen_event=select(2,safety.state())
local reached=false
for _=1,20 do
    now=now+1;safety.update()
    local progress=safety.state().backup
    if progress and progress.phase=="checksum" then reached=true;break end
end
check(reached,"Fixture did not reach immutable backup work")
save(false)
newest=select(2,safety.state()).id
now=now+1;safety.update()
check(frozen_event.backup=="verified" and safety.state().ack~=newest,"Older backup acknowledged a newer native save")
check(files["latest-save"].event.id==newest,"Older backup overwrote the newest native receipt")
finish_backup()
check(#store.catalog==catalog_before+2 and safety.state().ack==newest,"Overlapping saves starved a frozen backup")
-- A failed native start must never turn into a completed character archive.
catalog_before=#store.catalog;keep=store.committed.id
local refused=call(exec,{nil,request},99)
check(not refused,"The mod blocked the native start instead of observing its failure")
call(callback,{nil,request,99,99},0);finish_backup()
check(store.committed.id==keep and #store.catalog==catalog_before,"Failed native save was committed as a backup")
-- A crash after native completion but before its commit must retain the pending
-- snapshot, and a later startup must reserve its expanded capacity.
write_failure="/commit-"
local verified_before=store.committed.id
call(exec,{nil,request},11);call(callback,{nil,request,7,11},0);finish_backup()
local _,_,_,fault=safety.state();check(fault==nil and safety.state().backup_warning~=nil,"Backup failure should warn without disabling native saves")
check(store.committed.id==verified_before,"Commit failure replaced the verified backup")
check(real_archive.open("test",backend):capacity()==4)
check(call(exec,{nil,request},11)==false,"Commit fault must not block further native writes")
call(callback,{nil,request,7,11},0)
write_failure=nil
finish_backup()
check(safety.state().backup_warning==nil,"A subsequent backup should recover after a transient failure")
-- Small slot bookkeeping is a different safety boundary from bulk backups.
-- Native completion still runs, but a failed capacity marker must not be hidden
-- by a later successful snapshot or permit more writes under uncertain state.
write_failure="/native-commit-"
check(call(exec,{nil,request},11)==false,"Native save did not start")
local callback_ran=false
call(callback,{nil,request,7,11},0,function()callback_ran=true end)
write_failure=nil
finish_backup()
check(callback_ran and select(4,safety.state())~=nil,"Slot bookkeeping fault was cleared by backup completion")
check(call(exec,{nil,request},11)==true,"Uncertain slot bookkeeping permitted an unsafe subsequent write")
-- Corrupt activation must stay guarded, not silently disable preservation.
files.session={}
io.open=function()return {close=function()end}end
json={load_file=function()error("Broken JSON")end}
package.loaded["MHWAddSaveSlots.preservation"]=nil
local corrupt=require("MHWAddSaveSlots.preservation")
check(corrupt.enabled())
local _,_,_,activation_fault=corrupt.state();check(activation_fault~=nil)
check(call(exec,{nil,request},11)==true)
check(call("app.SaveDataManager:systemRequestUserLoad",{nil,manager,nil},0)==false,"Archive failure must leave native inspection available")
json.load_file=function()return {version=1,enabled=true,copy_acknowledged=true,profile="missing"}end
store.latest=nil;store.committed=nil;store.catalog={}
package.loaded["MHWAddSaveSlots.preservation"]=nil
local missing=require("MHWAddSaveSlots.preservation")
local _,_,_,missing_fault=missing.state();check(missing_fault~=nil,"Missing backup library must not reset capacity to three")
check(call(exec,{nil,request},11)==true)
print("Lua preservation checks passed: "..checks)
