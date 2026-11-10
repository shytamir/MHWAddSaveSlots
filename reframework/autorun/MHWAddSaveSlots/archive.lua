-- Immutable snapshots plus small publication/commit records. A publication is
-- written only after snapshot read-back succeeds. Commits follow native success.
-- Checksums detect accidental corruption; they are not authentication signatures.
local M={}
local policy=require("MHWAddSaveSlots.policy")
local codec=require("MHWAddSaveSlots.snapshot_codec")
function M.checksum(value,checkpoint)
    local hash=0x811c9dc5
    for first=1,#value,4096 do
        for i=first,math.min(first+4095,#value) do hash=((hash ~ value:byte(i))*0x01000193)&0xffffffff end
        if checkpoint then checkpoint("checksum") end
    end
    return string.format("%08x",hash)
end
local function id_ok(id)
    return type(id)=="string" and id:match("^%d+%-%d+%-%d+$")~=nil
end
local function native_checksum(meta)
    return M.checksum(table.concat({meta.id,tostring(meta.revision),tostring(meta.slots),
        tostring(meta.previous_slots),meta.purpose},"|"))
end
local function validate(snapshot)
    assert(type(snapshot)=="table" and snapshot.version==1 and id_ok(snapshot.id),"Invalid archive header")
    policy.count(snapshot.slots)
    assert(type(snapshot.revision)=="number" and snapshot.revision>=1 and snapshot.revision%1==0)
    assert(type(snapshot.entries)=="table" and #snapshot.entries==snapshot.slots,"Archive entry count differs")
    local sums={tostring(snapshot.slots)}
    for _,entry in ipairs(snapshot.entries) do
        codec.validate(entry)
        assert(entry.checksum==M.checksum(entry.data),"Character snapshot checksum mismatch")
        sums[#sums+1]=entry.checksum..":"..entry.bytes
    end
    assert(snapshot.checksum==M.checksum(table.concat(sums,"|")),"Archive checksum mismatch")
    return snapshot
end
local default_io={}
function default_io.read(path)
    local ok,value=pcall(json.load_file,path)
    assert(ok and type(value)=="table","Could not read archive: "..path)
    return value
end
function default_io.exists(path)
    local f=io.open(path,"rb"); if not f then return false end
    f:close(); return true
end
function default_io.write(path,value)
    assert(not default_io.exists(path),"Archive destination already exists")
    assert(json.dump_file(path,value)~=false,"Archive write failed")
end
-- Produce the existing v1 JSON format without building/parsing a second giant
-- JSON object. Exact byte read-back verifies the bytes just written; checksums
-- remain in the format for corruption checks on future loads.
function M.write_verified(io_api,path,snapshot,checkpoint)
    local function header(value)
        local text=io_api.encode_json(value)
        assert(type(text)=="string" and text:sub(-1)=="}","Archive JSON encoding failed")
        return text:sub(1,-2)
    end
    local pieces={header({version=snapshot.version,id=snapshot.id,revision=snapshot.revision,
        slots=snapshot.slots,label=snapshot.label,utc=snapshot.utc,checksum=snapshot.checksum})..',"entries":['}
    for i,entry in ipairs(snapshot.entries) do
        pieces[#pieces+1]=(i>1 and "," or "")..header({bytes=entry.bytes,name=entry.name,active=entry.active,checksum=entry.checksum})..',"data":"'
        pieces[#pieces+1]=entry.data
        pieces[#pieces+1]='"}'
    end
    pieces[#pieces+1]="]}"
    local file
    local ok,err=pcall(function()
        assert(not io_api.exists(path),"Archive destination already exists")
        file=assert(io_api.open(path,"wb"),"Could not open snapshot for writing")
        for _,piece in ipairs(pieces) do for first=1,#piece,16384 do
            assert(file:write(piece:sub(first,first+16383)),"Archive write failed")
            checkpoint("write")
        end end
        assert(file:close(),"Archive close failed");file=nil
        checkpoint("close",true)
        file=assert(io_api.open(path,"rb"),"Could not reopen snapshot")
        for _,piece in ipairs(pieces) do for first=1,#piece,16384 do
            local expected=piece:sub(first,first+16383)
            assert(file:read(#expected)==expected,"Snapshot byte read-back differs")
            checkpoint("read-back")
        end end
        assert(file:read(1)==nil,"Snapshot contains trailing bytes")
        assert(file:close(),"Archive read close failed");file=nil
    end)
    if file then pcall(file.close,file) end
    if not ok then error(err,0) end
end
default_io.open=function(path,mode) return io.open(path,mode) end
default_io.encode_json=function(value) return json.dump_string(value,-1) end
function default_io.list(prefix)
    local out={}
    for _,path in ipairs(fs.glob(".*(publish|native)-[0-9-]+\\.json$")) do
        local normalized=path:gsub("\\","/")
        if normalized:sub(1,#prefix)==prefix then out[#out+1]=normalized end
    end
    return out
end
function M.open(profile,backend)
    assert(type(profile)=="string" and profile:match("^[A-Za-z0-9-]+$"),"Invalid archive profile")
    local io_api=backend or default_io
    local prefix="MHWAddSaveSlots/libraries/"..profile.."/"
    local self={revision=0,latest=nil,committed=nil,catalog={},prefix=prefix}
    local verified
    local function path(kind,id)
        assert(id_ok(id),"Invalid archive ID")
        return prefix..kind.."-"..id..".json"
    end
    function self:load(id)
        local value=validate(io_api.read(path("snapshot",id)))
        assert(value.id==id,"Archive identity mismatch")
        return value
    end
    function self:scan()
        self.catalog={};self.latest=nil;self.committed=nil;self.native=nil;self.revision=0;verified=nil
        local revisions={}
        for _,file in ipairs(io_api.list(prefix.."publish-")) do
            local meta=io_api.read(file)
            assert(id_ok(meta.id) and file==path("publish",meta.id) and meta.version==1,"Invalid archive publication")
            policy.count(meta.slots)
            assert(type(meta.revision)=="number" and meta.revision%1==0 and meta.revision>0)
            assert(not revisions[meta.revision],"Archive has conflicting revisions")
            revisions[meta.revision]=true
            self.revision=math.max(self.revision,meta.revision)
            local marker=path("commit",meta.id)
            meta.committed=io_api.exists(marker)
            if meta.committed then
                local commit=io_api.read(marker)
                assert(commit.id==meta.id and commit.checksum==meta.checksum and commit.slots==meta.slots,"Archive commit differs")
                if not self.committed or meta.revision>self.committed.revision then self.committed=meta end
            end
            if not self.latest or meta.revision>self.latest.revision then self.latest=meta end
            self.catalog[#self.catalog+1]=meta
        end
        for _,file in ipairs(io_api.list(prefix.."native-")) do
            if file:sub(#prefix+1):match("^native%-%d+%-%d+%-%d+%.json$") then
                local meta=io_api.read(file)
                assert(meta.version==1 and id_ok(meta.id) and file==path("native",meta.id),"Invalid native capacity record")
                policy.count(meta.slots)
                policy.count(meta.previous_slots)
                assert(meta.purpose=="save" or meta.purpose=="trim","Invalid native save purpose")
                assert(type(meta.revision)=="number" and meta.revision%1==0 and meta.revision>0)
                assert(meta.checksum==native_checksum(meta),"Native capacity checksum differs")
                assert(not revisions[meta.revision],"Conflicting capacity revision")
                revisions[meta.revision]=true;self.revision=math.max(self.revision,meta.revision)
                local marker=path("native-commit",meta.id)
                meta.completed=io_api.exists(marker)
                if meta.completed then
                    local done=io_api.read(marker)
                    assert(done.version==1 and done.id==meta.id and done.slots==meta.slots and done.checksum==meta.checksum,"Native capacity completion differs")
                end
                if not self.native or meta.revision>self.native.revision then self.native=meta end
            end
        end
        table.sort(self.catalog,function(a,b) return a.revision>b.revision end)
        -- Verify the candidates that can influence startup before trusting counts.
        local checked={}
        for _,meta in pairs({self.latest,self.committed}) do
            if meta and not checked[meta.id] then local snapshot=self:load(meta.id)
                assert(snapshot.checksum==meta.checksum and snapshot.slots==meta.slots and snapshot.revision==meta.revision,"Publication differs from snapshot")
                checked[meta.id]=true
            end
        end
        return self
    end
    function self:capacity()
        local count=self.committed and self.committed.slots or 3
        local revision=self.committed and self.committed.revision or 0
        if self.native and self.native.revision>revision then
            count=self.native.completed and self.native.slots or math.max(count,self.native.slots,self.native.previous_slots)
            revision=self.native.revision
        end
        if self.latest and self.latest.revision>revision then
            count=math.max(count,self.latest.slots)
        end
        return policy.count(count)
    end
    local function next_id()
        self.revision=self.revision+1
        return string.format("%09d-%d-%d",self.revision,os.time(),math.random(100000,999999))
    end
    -- A small capacity intent is independent of the character backup. A crash
    -- after native success but before background publication must not restart
    -- with a stale three-entry capacity. This is not a character snapshot.
    function self:native_start(count,purpose)
        policy.count(count)
        assert(purpose=="save" or purpose=="trim","Invalid native save purpose")
        local previous=self:capacity()
        local id=next_id()
        local meta={version=1,id=id,revision=self.revision,slots=count,previous_slots=previous,purpose=purpose}
        meta.checksum=native_checksum(meta)
        io_api.write(path("native",id),meta)
        self.native=meta
        return id
    end
    function self:native_complete(id)
        local meta=assert(self.native and self.native.id==id and self.native,"Native save identity changed")
        local start=io_api.read(path("native",id))
        assert(start.id==id and start.slots==meta.slots and start.previous_slots==meta.previous_slots and start.revision==meta.revision
            and start.checksum==meta.checksum and native_checksum(start)==meta.checksum,"Native capacity intent differs")
        io_api.write(path("native-commit",id),{version=1,id=id,slots=meta.slots,checksum=meta.checksum})
        local done=io_api.read(path("native-commit",id))
        assert(done.id==id and done.slots==meta.slots and done.checksum==meta.checksum,"Native capacity completion failed")
        meta.completed=true
    end
    function self:capture(entries,label,checkpoint)
        local count=policy.count(#entries)
        local id=next_id()
        local snapshot={version=1,id=id,revision=self.revision,slots=count,label=label or "save",
            utc=os.date("!%Y-%m-%dT%H:%M:%SZ"),entries=entries}
        local sums={tostring(count)}
        for _,entry in ipairs(entries) do
            codec.validate(entry,checkpoint); entry.checksum=M.checksum(entry.data,checkpoint)
            sums[#sums+1]=entry.checksum..":"..entry.bytes
        end
        snapshot.checksum=M.checksum(table.concat(sums,"|"))
        local file=path("snapshot",id)
        assert(not io_api.exists(file),"Archive ID collision")
        if checkpoint and io_api.open and io_api.encode_json then
            M.write_verified(io_api,file,snapshot,checkpoint)
        else
            -- Synchronous title-menu operations and simple mocked backends.
            io_api.write(file,snapshot)
            local readback=self:load(id)
            assert(readback.checksum==snapshot.checksum,"Snapshot read-back differs")
            for i,entry in ipairs(entries) do assert(readback.entries[i].data==entry.data,"Snapshot byte read-back differs") end
        end
        local meta={version=1,id=id,revision=snapshot.revision,slots=count,checksum=snapshot.checksum,label=snapshot.label,utc=snapshot.utc}
        io_api.write(path("publish",id),meta)
        local published=io_api.read(path("publish",id))
        assert(published.id==id and published.checksum==meta.checksum and published.slots==count,"Archive publication verification failed")
        self.latest=meta; table.insert(self.catalog,1,meta)
        verified={id=id,slots=count,checksum=snapshot.checksum}
        return meta
    end
    function self:commit(id)
        -- capture has just verified the immutable bytes. Do not read/parse/hash
        -- the entire file again merely to write a small completion marker.
        local snapshot=verified and verified.id==id and verified or self:load(id)
        local file=path("commit",id)
        local value={version=1,id=id,slots=snapshot.slots,checksum=snapshot.checksum}
        if not io_api.exists(file) then io_api.write(file,value) end
        local readback=io_api.read(file)
        assert(readback.id==id and readback.slots==value.slots and readback.checksum==value.checksum,"Commit verification failed")
        for _,meta in ipairs(self.catalog) do if meta.id==id then
            meta.committed=true
            if not self.committed or meta.revision>self.committed.revision then self.committed=meta end
        end end
    end
    return self:scan()
end
return M
