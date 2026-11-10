-- Read-only, development-only observation for an isolated packaged-build test.
-- No hooks, character writes, selection changes, or save requests.
local control=require("MHWAddSaveSlots.control")
local records=require("MHWAddSaveSlots.records")
local session=control.read("session")
assert(session.isolated==true and type(session.session_id)=="string","Requires an isolated copied-save session")
local boot=tostring(os.time()).."-"..tostring(math.random(100000,999999))
local last=0
re.on_application_entry("UpdateBehavior",function()
    if os.clock()-last<1 then return end
    last=os.clock()
    local report={boot=boot,session_id=session.session_id,utc=os.date("!%Y-%m-%dT%H:%M:%SZ"),characters={}}
    local ok,err=pcall(function()
        local manager,_,slots,state=records.context()
        report.state=state and state:get_type_definition():get_full_name()
        report.current=manager and manager:get_field("CurrentUserDataIndex")
        report.busy=manager and records.busy(manager)
        local common=records.common(manager)
        report.persisted_index=common and common:get_field("LastUserIndex")
        if slots then
            for i=0,slots:get_size()-1 do
                local value=slots:get_element(i)
                local basic=value and value:get_field("_BasicData")
                report.characters[#report.characters+1]={index=i,active=value and value:get_field("Active"),
                    name=basic and basic:get_field("CharName"),palico=basic and basic:get_field("OtomoName")}
            end
        end
    end)
    if not ok then report.error=tostring(err)end
    control.write("package-observer",report)
end)
