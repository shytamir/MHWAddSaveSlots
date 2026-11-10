-- Cooperative work on UpdateBehavior, never a coroutine suspended inside a hook.
-- The budget limits work between checkpoints; a single engine/OS call cannot be
-- preempted. Keep those calls separate and record their observed cost.
local M={BUDGET_SECONDS=0.002,MAX_STEPS=8}
function M.new(fn,clock)
    clock=clock or os.clock
    local job={done=false,phase="queued",steps=0,frames=0,seconds=0,max_frame_seconds=0,stages={}}
    local cancelled={}
    local function checkpoint(phase,next_frame)
        coroutine.yield(phase,next_frame)
        if job.cancelled then error(cancelled,0) end
    end
    local worker=coroutine.create(function() return fn(checkpoint) end)
    function job:cancel() self.cancelled=true end
    function job:step()
        if self.done then return end
        if self.cancelled and self.steps==0 then self.done=true;return end
        local start=clock()
        self.frames=self.frames+1
        for _=1,M.MAX_STEPS do
            local before=clock()
            local ok,value,next_frame=coroutine.resume(worker)
            local elapsed=math.max(0,clock()-before)
            self.steps=self.steps+1
            if not ok then
                self.done=true
                if value~=cancelled then self.error=tostring(value) end
                break
            end
            if coroutine.status(worker)=="dead" then self.done=true;self.result=value;break end
            self.phase=value or "working"
            local stage=self.stages[self.phase] or {calls=0,seconds=0,max_seconds=0}
            stage.calls=stage.calls+1;stage.seconds=stage.seconds+elapsed
            stage.max_seconds=math.max(stage.max_seconds,elapsed);self.stages[self.phase]=stage
            if next_frame or clock()-start>=M.BUDGET_SECONDS then break end
        end
        local elapsed=math.max(0,clock()-start)
        self.seconds=self.seconds+elapsed
        self.max_frame_seconds=math.max(self.max_frame_seconds,elapsed)
    end
    function job:report()
        return {phase=self.phase,done=self.done,error=self.error,cancelled=self.cancelled==true,
            steps=self.steps,frames=self.frames,seconds=self.seconds,max_frame_seconds=self.max_frame_seconds,stages=self.stages}
    end
    return job
end
return M
