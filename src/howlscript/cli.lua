-- Copyright 2026 Nils Nordman
-- License: MIT (see LICENSE.md at the top-level directory of the distribution)

-- The howlscript command, which bin/howlscript runs. main() takes the streams to
-- use, so that the specs can run it.

local howlscript = require('howlscript')

local format, match, sub = string.format, string.match, string.sub
local unpack = table.unpack or unpack -- LuaJIT has only the global

local USAGE = [[
Usage: howlscript <command> [<arg>]...

Commands:
  compile  compile Howlscript to Lua
  run      run Howlscript
  help     show the help for a command

'howlscript help <command>' shows a command's options.
]]

local HELP = {
  compile = [[
Usage: howlscript compile [-p] [-o <file>] [-e <code>] [<file>|-]...

Compiles each Howlscript file to Lua, writing file.lua next to file.howl. Code given
with -e, and stdin ('-', or no inputs at all), are printed. Each statement of the
Lua starts on the line it starts on in the Howlscript. Exits with 1 if an input
doesn't compile.

  -p, --print          print the Lua instead of writing files
  -o, --output <file>  write the Lua to <file>, for a single input
  -e, --eval <code>    compile <code>
  -h, --help           show this help
]],

  run = [[
Usage: howlscript run (<file>|-e <code>|-) [<arg>]...

Runs a Howlscript file, code given with -e, or stdin ('-'), which can require .howl
modules. The arguments are in arg, with the file in arg[0], as for the lua command,
and are passed as ... .

  -e, --eval <code>  run <code>
  -h, --help         show this help
]],
}

local function read_file(path)
  local fh, err = io.open(path, 'rb')
  if not fh then return nil, err end
  local text = fh:read('*a')
  fh:close()
  return text
end

local function write_file(path, text)
  local fh, err = io.open(path, 'wb')
  if not fh then return nil, err end
  fh:write(text)
  fh:close()
  return true
end

-- The path of the Lua for a Howlscript file: file.lua for file.howl
local function lua_path(path)
  return (match(path, '^(.*)%.howl$') or path) .. '.lua'
end

local function failed(io_, message)
  io_.err:write('howlscript: ', message, '\n')
  return 1
end

local function compile(args, io_)
  local inputs, print_lua, output = {}, false, nil
  local i = 1
  while i <= #args do
    local a = args[i]
    if a == '-h' or a == '--help' then
      io_.out:write(HELP.compile)
      return 0
    elseif a == '-p' or a == '--print' then
      print_lua = true
    elseif a == '-o' or a == '--output' or a == '-e' or a == '--eval' then
      i = i + 1
      if not args[i] then return failed(io_, a .. ' needs an argument') end
      if a == '-o' or a == '--output' then
        output = args[i]
      else
        inputs[#inputs + 1] = { name = '(eval)', code = args[i] }
      end
    elseif a == '-' then
      inputs[#inputs + 1] = { name = '(stdin)', stdin = true }
    elseif sub(a, 1, 1) == '-' then
      return failed(io_, format("unknown option '%s' for compile", a))
    else
      inputs[#inputs + 1] = { name = a, path = a }
    end
    i = i + 1
  end
  if #inputs == 0 then inputs[1] = { name = '(stdin)', stdin = true } end
  if output and #inputs > 1 then return failed(io_, '-o takes a single input') end

  local printed = 0
  for _, input in ipairs(inputs) do
    if not (input.path or output) then printed = printed + 1 end
  end
  if print_lua and not output then printed = #inputs end

  local status = 0
  for _, input in ipairs(inputs) do
    local code, err = input.code, nil
    if input.stdin then
      code = io_.stdin:read('*a')
    elseif input.path then
      code, err = read_file(input.path)
    end
    local lua
    if code then
      local chunkname = input.path and '@' .. input.path or '=' .. input.name
      lua, err = howlscript.to_lua(code, { chunkname = chunkname })
    else
      err = 'howlscript: ' .. err
    end
    if lua then
      if sub(lua, -1) ~= '\n' then lua = lua .. '\n' end
      if output or (input.path and not print_lua) then
        local ok, write_err = write_file(output or lua_path(input.path), lua)
        if not ok then status = failed(io_, write_err) end
      else
        -- with several printed, each is named in a comment line before it
        if printed > 1 then io_.out:write('-- ', input.name, '\n') end
        io_.out:write(lua)
      end
    else
      io_.err:write(err, '\n')
      status = 1
    end
  end
  return status
end

local function run(args, io_)
  local first = args[1]
  if first == '-h' or first == '--help' then
    io_.out:write(HELP.run)
    return 0
  end
  if not first then return failed(io_, 'run needs a file, -e <code> or -') end

  local code, chunkname, err
  local rest = 2
  if first == '-e' or first == '--eval' then
    code, chunkname, rest = args[2], '=(eval)', 3
    if not code then return failed(io_, first .. ' needs an argument') end
  elseif first == '-' then
    code, chunkname = io_.stdin:read('*a'), '=(stdin)'
  elseif sub(first, 1, 1) == '-' then
    return failed(io_, format("unknown option '%s' for run", first))
  else
    code, err = read_file(first)
    if not code then return failed(io_, err) end
    chunkname = '@' .. first
  end

  local f
  f, err = howlscript.loadstring(code, chunkname)
  if not f then
    io_.err:write(err, '\n')
    return 1
  end

  local script_args = { [0] = rest == 3 and '-e' or first }
  for j = rest, #args do script_args[#script_args + 1] = args[j] end
  _G.arg = script_args
  howlscript.insert_loader()
  local ok, run_err = xpcall(function()
    return f(unpack(script_args, 1, #script_args))
  end, debug.traceback)
  if not ok then return failed(io_, tostring(run_err)) end
  return 0
end

local commands = { compile = compile, run = run }

-- Runs the command given by args (as in Lua's arg, from index 1), reading and
-- writing the given streams, which default to io's. Returns the exit status.
local function main(args, stdin, stdout, stderr)
  local io_ = { stdin = stdin or io.stdin, out = stdout or io.stdout, err = stderr or io.stderr }
  local name = args[1]
  local rest = {}
  for i = 2, #args do rest[#rest + 1] = args[i] end

  if name == nil then
    io_.err:write(USAGE)
    return 1
  elseif name == '-h' or name == '--help' or (name == 'help' and not rest[1]) then
    io_.out:write(USAGE)
    return 0
  elseif name == 'help' then
    if not HELP[rest[1]] then return failed(io_, format("no command '%s'", rest[1])) end
    io_.out:write(HELP[rest[1]])
    return 0
  end

  local command = commands[name]
  if not command then
    io_.err:write(format("howlscript: no command '%s'\n\n", name), USAGE)
    return 1
  end
  return command(rest, io_)
end

return {
  main = main,
}
