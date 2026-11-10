package.path="reframework/autorun/?.lua;"..package.path
local archive=require("MHWAddSaveSlots.archive")
local codec=require("MHWAddSaveSlots.snapshot_codec")
local checks=0
local function check(v,m) checks=checks+1;assert(v,m) end
local function rejects(fn) check(not pcall(fn),"Expected rejection") end
local function clone(v)
    if type(v)~="table" then return v end
    local out={};for k,x in pairs(v) do out[k]=clone(x) end;return out
end
local files,fail_write={},nil
local backend={exists=function(p)return files[p]~=nil end,
    read=function(p) assert(files[p],"Missing file");return clone(files[p]) end,
    write=function(p,v) assert(not files[p],"Overwrite refused");assert(not fail_write or not p:find(fail_write,1,true),"Injected write failure");files[p]=clone(v) end,
    list=function(prefix)local paths={};for p in pairs(files) do if p:sub(1,#prefix)==prefix and p:find("publish-",1,true) then paths[#paths+1]=p end end;return paths end}
local function entries(n)
    local out={};for i=1,n do out[i]={bytes=3,data="AQID",name="Fixture "..i,active=true} end;return out
end
check(archive.checksum("")=="811c9dc5")
check(archive.checksum("hello")=="4f9f2cab")
rejects(function()archive.open("../escape",backend)end)
rejects(function()codec.validate({bytes=3,data="A?ID"})end)
local store=archive.open("test",backend)
check(store:capacity()==3)
local three=store:capture(entries(3),"baseline");store:commit(three.id)
local five=store:capture(entries(5),"expanded");store:commit(five.id)
check(store:capacity()==5)
local sixteen=store:capture(entries(16),"interrupted save")
check(archive.open("test",backend):capacity()==16,"Uncommitted expansion must preserve startup capacity")
local trimmed=store:capture(entries(3),"trim");store:commit(trimmed.id)
local restarted=archive.open("test",backend)
check(restarted:capacity()==3,"Committed trim should select native capacity")
check(restarted:load(five.id).slots==5,"Trim must retain expanded snapshot")
check(restarted:load(sixteen.id).slots==16,"Interrupted expanded snapshot must remain available")
local count=0;for _ in pairs(files)do count=count+1 end
store:commit(trimmed.id)
local count2=0;for _ in pairs(files)do count2=count2+1 end
check(count==count2,"Repeated commit should not overwrite or duplicate")
fail_write="publish-"
rejects(function()store:capture(entries(6),"failed publication")end)
fail_write=nil
check(archive.open("test",backend):capacity()==3,"Incomplete unpublished snapshot cannot advance startup")
fail_write="snapshot-"
rejects(function()store:capture(entries(5),"disk full")end)
fail_write=nil
local file=store.prefix.."snapshot-"..trimmed.id..".json"
local intact=clone(files[file]);files[file].entries[1].data="BQID"
rejects(function()archive.open("test",backend)end)
files[file]=intact
local marker=store.prefix.."commit-"..trimmed.id..".json"
files[marker].slots=5
rejects(function()archive.open("test",backend)end)
files[marker].slots=3
check(archive.open("test",backend):capacity()==3)
rejects(function()store:load("../bad")end)
print("Archive checks passed: "..checks)
