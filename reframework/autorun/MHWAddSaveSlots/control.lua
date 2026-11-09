local M={}
function M.read(name)
    local file=io.open("MHWAddSaveSlots."..name..".json","r")
    if not file then return {} end
    file:close()
    local ok,result=pcall(json.load_file,"MHWAddSaveSlots."..name..".json")
    return ok and type(result)=="table" and result or {}
end
function M.enabled(session)
    return session.isolated==true and session.mutation_enabled==true
        and type(session.session_id)=="string" and #session.session_id>0
        and type(session.expires_utc)=="string"
        and os.date("!%Y-%m-%dT%H:%M:%S")<session.expires_utc
end
return M
