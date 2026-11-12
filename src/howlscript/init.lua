-- Copyright 2026 Nils Nordman
-- License: MIT (see LICENSE.md at the top-level directory of the distribution)

-- Howlscript compiles to Lua. See REFERENCE.md in this directory for the language.

local lexer = require('howlscript.lexer')
local parser = require('howlscript.parser')
local compiler = require('howlscript.compiler')
local errors = require('howlscript.errors')

local format, gsub, sub = string.format, string.gsub, string.sub

local function read_file(path)
  local fh, err = io.open(path, 'rb')
  if not fh then return nil, err end
  local source = fh:read('*a')
  fh:close()
  return source
end

-- Compiles Howlscript source to Lua. Returns the Lua code, or nil, an error message
-- and the error as a table: { line, col, len, message }, where `col` is a byte
-- column and `len`, if known, the length in bytes of what the error is about.
-- `opts.chunkname` names the source in error messages, as Lua chunk names do
-- ('@path' or '=name').
local function to_lua(source, opts)
  opts = opts or {}
  local ok, result = xpcall(function()
    return compiler.compile(parser.parse(lexer.lex(source)), source)
  end, function(err)
    if errors.is_compile_error(err) then return err end
    return debug.traceback(err, 2)
  end)

  if ok then return result end
  if errors.is_compile_error(result) then
    local err = { line = result.line, col = result.col, len = result.len, message = result.message }
    return nil, errors.format(result, source, opts.chunkname), err
  end
  error('howlscript: internal compiler error: ' .. tostring(result), 0)
end

-- Like Lua's loadstring: returns a function running the source, or nil and an
-- error message. `env`, if given, is set as the function's environment.
local function hs_loadstring(source, chunkname, env)
  chunkname = chunkname or '=(howlscript)'
  local lua, err = to_lua(source, { chunkname = chunkname })
  if not lua then return nil, err end
  -- an explicit nil would be taken as the environment
  local f, lua_err
  if env then
    f, lua_err = load(lua, chunkname, 't', env)
  else
    f, lua_err = load(lua, chunkname, 't')
  end
  if not f then
    -- the compiler produced invalid Lua, which is a bug in the compiler
    error('howlscript: internal compiler error: ' .. lua_err, 0)
  end
  return f
end

local function hs_loadfile(path, env)
  path = tostring(path)
  local source, err = read_file(path)
  if not source then return nil, err end
  return hs_loadstring(source, '@' .. path, env)
end

local function hs_dofile(path, ...)
  return assert(hs_loadfile(path))(...)
end

local searchers = package.searchers or package.loaders -- LuaJIT's are loaders

-- Finds a module for `require` along package.howlpath, returning it compiled, or
-- why it isn't there.
local function searcher(name)
  local path, not_found = package.searchpath(name, package.howlpath or '')
  if not path then return not_found end
  local f, err = hs_loadfile(path)
  if not f then
    error(format("error loading module '%s' from file '%s':\n\t%s", name, path, err), 0)
  end
  return f, path
end

local function loader_index()
  for i, s in ipairs(searchers) do
    if s == searcher then return i end
  end
end

-- Lets `require` load Howlscript modules, which it then looks for along
-- package.howlpath before it looks for Lua ones. Unless it's set already,
-- package.howlpath is set to package.path with .howl in place of .lua. Returns false
-- if the loader is in place already.
local function insert_loader()
  if not package.howlpath then
    package.howlpath = sub(gsub(package.path .. ';', '%.lua;', '.howl;'), 1, -2)
  end
  if loader_index() then return false end
  table.insert(searchers, 2, searcher)
  return true
end

-- Takes out the loader that insert_loader puts in, returning false if it isn't in.
local function remove_loader()
  local i = loader_index()
  if not i then return false end
  table.remove(searchers, i)
  return true
end

return {
  to_lua = to_lua,
  loadstring = hs_loadstring,
  loadfile = hs_loadfile,
  dofile = hs_dofile,
  insert_loader = insert_loader,
  remove_loader = remove_loader,
}
