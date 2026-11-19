-- Copyright 2026 Nils Nordman
-- License: MIT (see LICENSE.md at the top-level directory of the distribution)
--
-- Makes the manual's pages for the website, run by scripts/site as
--
--   lua make-manual.lua <stylua> <stylua.toml> <output dir> <chapter.md>...
--
-- Each chapter is copied to the output directory, with its Howlscript examples
-- given a Lua tab: each ```howl block at the start of a line becomes a pair of
-- tabs, Howlscript and the Lua it compiles to for Lua 5.4, laid out by StyLua,
-- without the body of the class support classes bring along. Blocks showing
-- compile errors (`-- error:`) and blocks fenced as ```howl,no-lua
-- are left alone. Any other block that doesn't compile is an error, naming the
-- chapter and line.

local dir = arg[0]:match('^(.*)/[^/]*$') or '.'
package.path = dir .. '/../src/?.lua;' .. dir .. '/../src/?/init.lua;' .. package.path

local howlscript = require('howlscript')

local TARGET = '5.4'
local LABEL = 'Lua 5.4'

local stylua, config, out_dir = arg[1], arg[2], arg[3]

local function fail(msg)
  io.stderr:write('make-manual: ', msg, '\n')
  os.exit(1)
end

local function read(path)
  local f = assert(io.open(path, 'rb'))
  local text = f:read('*a')
  f:close()
  return text
end

local function write(path, text)
  local f = assert(io.open(path, 'wb'))
  f:write(text)
  f:close()
end

local function lines_of(text)
  local lines = {}
  for line in (text .. '\n'):gmatch('([^\n]*)\n') do
    lines[#lines + 1] = line
  end
  if lines[#lines] == '' then lines[#lines] = nil end
  return lines
end

-- The compiled Lua keeps each statement on its source line, so a source line that
-- compiles to nothing, like a table's closing brace, leaves an empty line. Those go,
-- so that only the source's own blank lines separate statements. Not in a block with
-- a long string, which can hold empty lines of its own.
local function drop_padding(lua, source)
  if source:find('[[', 1, true) then return lua end
  local src_lines = lines_of(source)
  local kept = {}
  for nr, line in ipairs(lines_of(lua)) do
    if line:find('%S') or not (src_lines[nr] or ''):find('%S') then
      kept[#kept + 1] = line
    end
  end
  return table.concat(kept, '\n') .. '\n'
end

-- Splits a chapter into parts: plain text, and the examples to give Lua tabs
local function parse(path)
  local parts, text = {}, {}
  local lines = lines_of(read(path))
  local i = 1
  while i <= #lines do
    local line = lines[i]
    local info = line:match('^```howl(.*)$')
    if info then
      local first, body = i, {}
      i = i + 1
      while lines[i] and lines[i] ~= '```' do
        body[#body + 1] = lines[i]
        i = i + 1
      end
      if not lines[i] then fail(path .. ':' .. first .. ': unclosed ```howl block') end
      local source = table.concat(body, '\n') .. '\n'
      if info == ',no-lua' then
        text[#text + 1] = '```howl\n' .. source .. '```'
      elseif info ~= '' then
        fail(path .. ':' .. first .. ": unknown fence '```howl" .. info .. "'")
      elseif source:find('%-%- error:') then
        text[#text + 1] = line .. '\n' .. source .. '```'
      else
        parts[#parts + 1] = table.concat(text, '\n')
        text = {}
        parts[#parts + 1] = {source = source, line = first + 1}
      end
    else
      text[#text + 1] = line
    end
    i = i + 1
  end
  parts[#parts + 1] = table.concat(text, '\n') .. '\n'
  return parts
end

-- A class with a parent, properties or metamethods brings Howlscript's runtime
-- support for classes along, some 150 lines prepended to the Lua, which would bury
-- the example's own. Its body is left out, which StyLua's layout makes easy to find:
-- `local __hs_setup`, `do`, and an `end` at the start of a line
local function elide_class_support(lua)
  local head, body, rest = lua:match('^(local __hs_setup\ndo\n)(.-\n)(end\n.*)$')
  if not head then return lua end
  local _, lines = body:gsub('\n', '')
  return head .. "  -- Howlscript's support for classes, " .. lines ..
    ' lines left out here\n' .. rest
end

local function shell_quote(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

local chapters, blocks = {}, {}
local tmp = os.tmpname()

for n = 4, #arg do
  local path = arg[n]
  local parts = parse(path)
  for _, part in ipairs(parts) do
    if type(part) == 'table' then
      local lua, err = howlscript.to_lua(part.source, {target = TARGET})
      if not lua then
        -- the message starts with the block's line, which becomes the chapter's
        local line, rest = err:match('^[^:]*:(%d+):(.*)$')
        fail(path .. ':' .. (line and part.line + line - 1 or part.line) .. ':' .. (rest or err))
      end
      part.file = tmp .. '-' .. (#blocks + 1) .. '.lua'
      write(part.file, drop_padding(lua, part.source))
      blocks[#blocks + 1] = part
    end
  end
  chapters[#chapters + 1] = {path = path, parts = parts}
end

if #blocks > 0 then
  local files = {}
  for i, block in ipairs(blocks) do files[i] = shell_quote(block.file) end
  local cmd = shell_quote(stylua) .. ' --config-path ' .. shell_quote(config) .. ' ' ..
    table.concat(files, ' ')
  local ok = os.execute(cmd)
  if ok ~= true and ok ~= 0 then fail('StyLua failed on the compiled examples') end
end

for _, chapter in ipairs(chapters) do
  local out, tabs = {}, 0
  for _, part in ipairs(chapter.parts) do
    if type(part) == 'string' then
      out[#out + 1] = part
    else
      tabs = tabs + 1
      local id = 'code-' .. tabs
      local lua = elide_class_support(read(part.file))
      os.remove(part.file)
      -- Tabs without JavaScript: radio buttons and labels before the two blocks, so
      -- the CSS can show the block of the checked one
      out[#out + 1] = table.concat({
        '<div class="code-tabs">',
        '<input type="radio" name="' .. id .. '" id="' .. id .. '-howl" checked>' ..
          '<label for="' .. id .. '-howl">Howlscript</label>',
        '<input type="radio" name="' .. id .. '" id="' .. id .. '-lua">' ..
          '<label for="' .. id .. '-lua">' .. LABEL .. '</label>',
        '',
        '```howl',
        part.source .. '```',
        '',
        '```lua',
        lua .. '```',
        '',
        '</div>',
        '', -- or a line right after it would belong to the HTML
      }, '\n')
    end
  end
  local name = chapter.path:match('[^/]*$')
  write(out_dir .. '/' .. name, table.concat(out, '\n'))
end
os.remove(tmp)
