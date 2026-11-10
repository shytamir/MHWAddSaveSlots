-- Immutable snapshots plus small publication/commit records. A publication is
-- written only after snapshot read-back succeeds. Commits follow native success.
-- Checksums detect accidental corruption; they are not authentication signatures.
local M={}
local policy=require("MHWAddSaveSlots.policy")
local codec=require("MHWAddSaveSlots.snapshot_codec")
function M.checksum(value)
    local hash=0x811c9dc5
    for i=1,#value do hash=((hash ~ value:byte(i))*0x01000193)&0xffffffff end
    return string.format("%08x",hash)
end
local function id_ok(id)
    return type(id)=="string" and id:match("^%d+%-%d+%-%d+$")~=nil
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
function default_io.list(prefix)
    local out={}
    for _,path in ipairs(fs.glob(".*publish-[0-9-]+\\.json$")) do
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
        self.catalog={};self.latest=nil;self.committed=nil;self.revision=0
        local revisions={}
        for _,file in ipairs(io_api.list(prefix)) do
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
        table.sort(self.catalog,function(a,b) return a.revision>b.revision end)
        -- Verify the candidates that can influence startup before trusting counts.
        for _,meta in ipairs({self.latest,self.committed}) do
            if meta then local snapshot=self:load(meta.id)
                assert(snapshot.checksum==meta.checksum and snapshot.slots==meta.slots and snapshot.revision==meta.revision,"Publication differs from snapshot")
            end
        end
        return self
    end
    function self:capacity()
        local count=self.committed and self.committed.slots or 3
        if self.latest and (not self.committed or self.latest.revision>self.committed.revision) then
            count=math.max(count,self.latest.slots)
        end
        return policy.count(count)
    end
    function self:capture(entries,label)
        local count=policy.count(#entries)
        self.revision=self.revision+1
        local id=string.format("%09d-%d-%d",self.revision,os.time(),math.random(100000,999999))
        local snapshot={version=1,id=id,revision=self.revision,slots=count,label=label or "save",
            utc=os.date("!%Y-%m-%dT%H:%M:%SZ"),entries=entries}
        local sums={tostring(count)}
        for _,entry in ipairs(entries) do
            codec.validate(entry); entry.checksum=M.checksum(entry.data)
            sums[#sums+1]=entry.checksum..":"..entry.bytes
        end
        snapshot.checksum=M.checksum(table.concat(sums,"|"))
        local file=path("snapshot",id)
        assert(not io_api.exists(file),"Archive ID collision")
        io_api.write(file,snapshot)
        local readback=self:load(id)
        assert(readback.checksum==snapshot.checksum,"Snapshot read-back differs")
        for i,entry in ipairs(entries) do assert(readback.entries[i].data==entry.data,"Snapshot byte read-back differs") end
        local meta={version=1,id=id,revision=self.revision,slots=count,checksum=snapshot.checksum,label=snapshot.label,utc=snapshot.utc}
        io_api.write(path("publish",id),meta)
        local published=io_api.read(path("publish",id))
        assert(published.id==id and published.checksum==meta.checksum and published.slots==count,"Archive publication verification failed")
        self.latest=meta; table.insert(self.catalog,1,meta)
        return meta
    end
    function self:commit(id)
        local snapshot=self:load(id)
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
