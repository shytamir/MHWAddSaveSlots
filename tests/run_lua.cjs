// Fengari runner with JSON bindings for storage tests. Unlike the old CLI, a
// failed Lua assertion produces a failing process exit code. No game APIs here.
const path = require('path');
let fengari;
try { fengari = require('fengari'); }
catch { fengari = require(path.resolve('work/lua-tools/node_modules/fengari')); }
const {lua, lauxlib, lualib, to_luastring, to_jsstring} = fengari;
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
function read(L,index) {
  index = lua.lua_absindex(L, index);
  switch (lua.lua_type(L,index)) {
    case lua.LUA_TNIL: return null;
    case lua.LUA_TBOOLEAN: return lua.lua_toboolean(L,index);
    case lua.LUA_TNUMBER: return lua.lua_tonumber(L,index);
    case lua.LUA_TSTRING: return to_jsstring(lua.lua_tostring(L,index));
    case lua.LUA_TTABLE: {
      const items = [];
      lua.lua_pushnil(L);
      while(lua.lua_next(L,index)) { items.push([read(L,-2),read(L,-1)]);lua.lua_pop(L,1); }
      if(items.length && items.every(([key])=>Number.isInteger(key)&&key>=1&&key<=items.length)) {
        const out=[]; for(const [key,value] of items) out[key-1]=value; return out;
      }
      return Object.fromEntries(items);
    }
    default: throw Error('Unsupported JSON fixture value');
  }
}
function push(L,value) {
  if(value===null) lua.lua_pushnil(L);
  else if(typeof value==='boolean') lua.lua_pushboolean(L,value);
  else if(typeof value==='number') {
    if(Number.isInteger(value)) lua.lua_pushinteger(L,value); else lua.lua_pushnumber(L,value);
  } else if(typeof value==='string') lua.lua_pushstring(L,to_luastring(value));
  else {
    lua.lua_newtable(L);
    for(const [key,item] of Object.entries(value)) {
      if(Array.isArray(value)) lua.lua_pushinteger(L,Number(key)+1); else lua.lua_pushstring(L,to_luastring(key));
      push(L,item);lua.lua_settable(L,-3);
    }
  }
}
lua.lua_newtable(L);
for(const [name,fn] of Object.entries({dump_string:state=>JSON.stringify(read(state,1)),load_string:state=>JSON.parse(read(state,1))})) {
  lua.lua_pushcfunction(L,state=>{try{push(state,fn(state));return 1;}catch(err){return lauxlib.luaL_error(state,to_luastring('%s'),to_luastring(String(err)));}});
  lua.lua_setfield(L,-2,to_luastring(name));
}
lua.lua_setglobal(L,to_luastring('json'));
const file=process.argv[2];
if(!file) throw Error('Usage: node tests/run_lua.cjs tests/test_name.lua');
const status=lauxlib.luaL_loadfile(L,to_luastring(file)) || lua.lua_pcall(L,0,lua.LUA_MULTRET,0);
if(status!==lua.LUA_OK) {
  const error=lua.lua_tostring(L,-1);
  process.stderr.write((error?to_jsstring(error):'Lua failed with a non-string error')+'\n');
  process.exitCode=1;
}
lua.lua_close(L);
