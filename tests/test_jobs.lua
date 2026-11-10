package.path="reframework/autorun/?.lua;"..package.path
local jobs=require("MHWAddSaveSlots.jobs")
local n=0
local function check(v,m) n=n+1;assert(v,m) end
local now,units=0,0
local job=jobs.new(function(yield)
    for _=1,20 do units=units+1;now=now+0.001;yield("work") end
    return "done"
end,function()return now end)
check(units==0,"Task ran before update")
job:step();check(units==2 and not job.done,"CPU budget was not honored")
while not job.done do job:step() end
check(job.result=="done" and units==20)
local count=0
local capped=jobs.new(function(yield) for _=1,100 do count=count+1;yield("chunk") end end,function()return 0 end)
capped:step();check(count==jobs.MAX_STEPS,"Constant clock bypassed step limit")
local calls=0
local engine=jobs.new(function(yield) for _=1,3 do calls=calls+1;yield("engine",true) end end)
engine:step();check(calls==1,"Multiple engine calls ran in one frame")
local closed=false
local cancel=jobs.new(function(yield)
    local ok,err=pcall(function()yield("file open",true);error("Should not continue")end)
    closed=true
    if not ok then error(err,0) end
end)
cancel:step();cancel:cancel();cancel:step()
check(cancel.done and cancel.cancelled and not cancel.error and closed,"Cancellation failed to clean up")
local ran=false
local early=jobs.new(function()ran=true end);early:cancel();early:step()
check(early.done and not ran,"Cancelled queued job ran")
local bad=jobs.new(function()error("injected")end);bad:step()
check(bad.done and bad.error:find("injected",1,true),"Worker error disappeared")
print("Job checks passed: "..n)
