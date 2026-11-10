-- Run with tests/run_lua.cjs: real JSON syntax, synthetic bytes and file handles.
package.path="reframework/autorun/?.lua;"..package.path
local archive=require("MHWAddSaveSlots.archive")
local jobs=require("MHWAddSaveSlots.jobs")
local checks=0
local function check(v,m)checks=checks+1;assert(v,m)end
local function rejects(fn)check(not pcall(fn),"Expected rejection")end
local files,reads={},{}
local open_handles,max_write,max_read=0,0,0
local fail_write,corrupt_read,fail_close=false,false,false
local backend={exists=function(p)return files[p]~=nil end,
    encode_json=json.dump_string,
    read=function(p)reads[p]=(reads[p] or 0)+1;return assert(json.load_string(assert(files[p])))end,
    write=function(p,v)assert(not files[p]);files[p]=json.dump_string(v)end,
    list=function(prefix)local out={} for p in pairs(files)do if p:sub(1,#prefix)==prefix then out[#out+1]=p end end return out end}
function backend.open(p,mode)
    if mode=="wb" then assert(not files[p]);files[p]="" else assert(files[p]) end
    open_handles=open_handles+1
    local offset,closed=1,false
    return {
        write=function(self,text)
            assert(not closed);max_write=math.max(max_write,#text)
            if fail_write then return nil,"injected write error" end
            files[p]=files[p]..text;return self
        end,
        read=function(_,count)
            assert(not closed);max_read=math.max(max_read,count)
            if offset>#files[p] then return nil end
            local out=files[p]:sub(offset,offset+count-1);offset=offset+#out
            if corrupt_read and #out>0 then out="!"..out:sub(2) end
            return out
        end,
        close=function()if not closed then closed=true;open_handles=open_handles-1 end;return not fail_close end}
end
local function entries(n)
    local out={};for i=1,n do out[i]={bytes=15000,data=string.rep("AQID",5000),name='Hunter "雪"\n'..i,active=i~=n} end;return out
end
local function drain(job)
    for _=1,10000 do if job.done then return end;job:step() end
    error("Job did not terminate")
end
local store=archive.open("stream",backend)
local baseline=store:capture(entries(3),"baseline");store:commit(baseline.id)
local baseline_bytes=files[store.prefix.."snapshot-"..baseline.id..".json"]
local fresh=entries(4)
check(archive.checksum(fresh[1].data)=="99c9ea65","Checksum changed across chunk boundaries")
local job=jobs.new(function(yield)local meta=store:capture(fresh,"after native save",yield);store:commit(meta.id);return meta end)
job:step()
check(not job.done and store.committed.id==baseline.id,"Incomplete snapshot replaced verified backup")
drain(job);check(not job.error,job.error)
local latest=job.result
check(latest.slots==4 and store.committed.id==latest.id)
check(max_write<=16384 and max_read<=16384,"Unbounded file operation")
check(open_handles==0,"File handle leaked")
local file=store.prefix.."snapshot-"..latest.id..".json"
check(not reads[file],"Streaming capture/commit reparsed the full JSON snapshot")
local loaded=store:load(latest.id)
check(loaded.entries[1].name==fresh[1].name and loaded.entries[4].data==fresh[4].data,"JSON round trip differs")
check(files[store.prefix.."snapshot-"..baseline.id..".json"]==baseline_bytes,"Previous verified snapshot was modified")
check(archive.open("stream",backend):capacity()==4,"New format is not reloadable")
local prior=store.committed.id
for _,failure in ipairs({"write","read","close"}) do
    fail_write=failure=="write";corrupt_read=failure=="read";fail_close=failure=="close"
    local failed=jobs.new(function(yield)local meta=store:capture(entries(5),"failure",yield);store:commit(meta.id)end)
    drain(failed)
    check(failed.error~=nil,"Injected "..failure.." failure was ignored")
    check(store.committed.id==prior and open_handles==0,"Failure replaced backup or leaked a handle")
    check(archive.open("stream",backend):capacity()==4,"Unpublished partial file became authoritative")
end
fail_write=false;corrupt_read=false;fail_close=false
local interrupted=jobs.new(function(yield)local meta=store:capture(entries(5),"cancelled",yield);store:commit(meta.id)end)
repeat interrupted:step() until open_handles>0 or interrupted.done
check(not interrupted.done,"Expected an open write")
interrupted:cancel();drain(interrupted)
check(interrupted.cancelled and not interrupted.error and open_handles==0,"Cancellation leaked a partial write")
check(store.committed.id==prior,"Cancellation replaced verified backup")
-- Native expansion and trim survive a restart even if the newest backup never
-- started. Failure before native completion reserves capacity conservatively.
local capacity=store:native_start(6,"save")
check(archive.open("stream",backend):capacity()==6,"Native intent lost expanded capacity")
store:native_complete(capacity)
check(archive.open("stream",backend):capacity()==6,"Native success required a finished backup")
local trim=store:native_start(3,"trim")
check(archive.open("stream",backend):capacity()==6,"Incomplete trim discarded the last native expanded capacity")
store:native_complete(trim)
check(archive.open("stream",backend):capacity()==3,"Completed native trim requires its backup to restart")
check(store:load(prior).slots==4,"Trim discarded expanded archive")
local older=jobs.new(function(yield)local meta=store:capture(entries(3),"older frozen save",yield);store:commit(meta.id)end)
older:step()
check(not older.done,"Expected an unfinished older backup")
local newer=store:native_start(7,"save");store:native_complete(newer)
drain(older);check(not older.error,older.error)
check(store:capacity()==7 and archive.open("stream",backend):capacity()==7,"Older backup completion reduced newer native capacity")
local marker=store.prefix.."native-commit-"..trim..".json"
local intact=files[marker];files[marker]=json.dump_string({version=1,id=trim,slots=5})
rejects(function()archive.open("stream",backend)end);files[marker]=intact
local intent=store.prefix.."native-"..trim..".json"
intact=files[intent]
local damaged=json.load_string(intact);damaged.previous_slots=17;files[intent]=json.dump_string(damaged)
rejects(function()archive.open("stream",backend)end);files[intent]=intact
print("Streaming archive checks passed: "..checks)
