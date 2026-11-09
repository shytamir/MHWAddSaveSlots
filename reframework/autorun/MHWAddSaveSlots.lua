-- Fixed-module dispatcher. Isolated test sessions can reload our modules without
-- resetting unrelated mods. Requests cannot provide filenames or arbitrary code.
local modules = {"MHWAddSaveSlots.compat", "MHWAddSaveSlots.probe", "MHWAddSaveSlots.poc"}
local control=require("MHWAddSaveSlots.control")
local loaded, last_nonce, last_poll = {}, nil, 0
local function reload()
    for _,n in ipairs(modules) do
        package.loaded[n] = nil
        local ok, m = pcall(require,n)
        if ok then loaded[n]=m else log.error(n..": "..tostring(m)) end
    end
end
reload()
re.on_application_entry("UpdateBehavior",function()
    if os.clock()-last_poll>1 then
        last_poll=os.clock()
        local session=control.read("session")
        local request=control.read("dev")
        if control.enabled(session) and request.session_id==session.session_id
            and request.reload_nonce and request.reload_nonce~=last_nonce then
            last_nonce=request.reload_nonce
            reload()
        end
    end
    for n,m in pairs(loaded) do
        local ok,err=pcall(m.update)
        if not ok then log.error(n..": "..tostring(err)) end
    end
end)
re.on_draw_ui(function()
    for _,m in pairs(loaded) do
        local ok,err=pcall(m.draw)
        if not ok then imgui.text(tostring(err)) end
    end
end)
