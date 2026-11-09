-- Restart Wilds after updating these files. Hot reload is intentionally absent:
-- replacing a stateful save hook midway through a transaction is unsafe.
local loaded={}
for _,name in ipairs({"probe","compat","poc"}) do
    local ok,module=pcall(require,"MHWAddSaveSlots."..name)
    if ok then loaded[#loaded+1]=module else
        log.error("MHWAddSaveSlots."..name..": "..tostring(module))
        if name=="compat" then
            local error_message=tostring(module)
            re.on_draw_ui(function() imgui.text("MHWAddSaveSlots unavailable: "..error_message) end)
            break
        end
    end
end
re.on_application_entry("UpdateBehavior",function()
    for _,module in ipairs(loaded) do
        local ok,err=pcall(module.update)
        if not ok then log.error("MHWAddSaveSlots: "..tostring(err)) end
    end
end)
re.on_draw_ui(function()
    for _,module in ipairs(loaded) do
        local ok,err=pcall(module.draw)
        if not ok then imgui.text(tostring(err)) end
    end
end)
