local M={}
local policy=require("MHWAddSaveSlots.policy")
function M.new()
    local td=assert(sdk.find_type_definition("app.savedata.cUserSaveParam"))
    local value=assert(td:get_method("create"):call(nil),"Character factory failed")
    value:add_ref()
    value:call("init")
    return value
end
function M.array(old, count)
    policy.count(count)
    local result=assert(sdk.create_managed_array("app.savedata.cUserSaveParam",count))
    result:add_ref()
    for i=0,count-1 do
        result[i]=i<old:get_size() and old:get_element(i) or M.new()
        assert(result:get_element(i),"Missing character record")
    end
    return result
end
function M.resize(root, count)
    local old=assert(root:get_field("_Data"))
    if old:get_size()~=count then root:set_field("_Data",M.array(old,count)) end
end
function M.context()
    local manager=sdk.get_managed_singleton("app.SaveDataManager")
    local flow=sdk.get_managed_singleton("app.GameFlowManager")
    local state=flow and flow:get_field("_CurrentGameState")
    local root=manager and manager:get_field("_UserSaveData")
    return manager,root,root and root:get_field("_Data"),state
end
function M.busy(manager)
    return manager:call("get_IsSaveRunning") or manager:call("get_IsSaveLoadFlowRunning")
end
function M.common(manager)
    local data=manager and manager:get_field("_SystemSaveData")
    local param=data and data:get_field("_Data")
    return param and param:get_field("_SystemCommon")
end
function M.audit(root, original)
    local seen,stack,count={},{root},0
    local function push(obj)
        if type(obj)~="userdata" then return end
        local ok,t=pcall(function() return obj:get_type_definition() end)
        if ok and t and not t:is_value_type() and t:get_full_name()~="System.String" then stack[#stack+1]=obj end
    end
    while #stack>0 do
        local obj=table.remove(stack)
        local key=tostring(obj:get_address())
        if not seen[key] then
            assert(not original or not original[key],"Clone shares a mutable object with its source")
            seen[key]=true; count=count+1
            assert(count<=500000,"Object graph exceeds audit limit")
            local t=obj:get_type_definition()
            if t:is_array() then
                for i=0,obj:get_size()-1 do push(obj:get_element(i)) end
            else
                while t do
                    for _,f in ipairs(t:get_fields()) do if not f:is_static() then push(f:get_data(obj)) end end
                    t=t:get_parent_type()
                end
            end
        end
    end
    return seen,count
end
return M
