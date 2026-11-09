-- Pure policy; exercised without the game by tests/test_safety.lua.
local M = {NATIVE_SLOTS=3, MAX_SLOTS=16, HEARTBEAT_SECONDS=10}
function M.count(n)
    assert(type(n)=="number" and n%1==0 and n>=3 and n<=M.MAX_SLOTS,
        "Unsupported capacity (expected 3.."..M.MAX_SLOTS..")")
    return n
end
function M.index(n, count)
    assert(type(n)=="number" and n%1==0 and n>=0 and n<count,"Invalid character index")
    return n
end
function M.native_index(value, fallback)
    if type(value)=="number" and value%1==0 and value>=0 and value<3 then return value end
    if type(fallback)=="number" and fallback%1==0 and fallback>=0 and fallback<3 then return fallback end
    return 0
end
function M.ready(status, session_id, now)
    return status.session_id==session_id and status.ready==true
        and type(status.heartbeat)=="number" and now>=status.heartbeat
        and now-status.heartbeat<=M.HEARTBEAT_SECONDS
        and type(status.snapshot)=="string" and #status.snapshot>0
end
function M.can_save(count, status, event, runtime_id, trim)
    M.count(count)
    if event and event.phase~="failed" and event.phase~="idle" then
        assert(event.phase=="completed" and status.ack==event.id,
            "Waiting for the backup companion to preserve the previous save")
    end
    if count<status.slots then
        assert(count==3 and trim and trim.runtime_id==runtime_id and trim.source==status.snapshot
            and trim.stage=="prepared" and status.trim_ack==trim.id,
            "Capacity reduction requires a verified trim transaction")
    end
    return true
end
return M
