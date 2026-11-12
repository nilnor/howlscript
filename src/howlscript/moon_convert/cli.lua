-- Copyright 2026 Nils Nordman
-- License: MIT (see LICENSE.md at the top-level directory of the distribution)

-- The howlscript-moon-convert command, which bin/howlscript-moon-convert runs.
-- main() takes the streams to use, so that the specs can run it.

local howlscript = require('howlscript')
local moon_convert = require('howlscript.moon_convert')

local format, gsub, match = string.format, string.gsub, string.match

local HELP = [[
Usage: howlscript-moon-convert [-w] [--spec] [--copyright] <file.moon>...

Converts MoonScript to Howlscript and prints the result. Warnings for what needs a
look, and errors compiling the result, go to stderr, and make it exit with 1.

  -w, --write    write <name>.howl next to each file and remove <name>.moon (with
                 git rm when it's tracked)
  --spec         convert every file as a busted spec, leaving busted's calls
                 without parentheses (the default for files named *_spec.moon)
  --copyright    end the years of Nils Nordman's copyrights with this year, and give
                 a file without a copyright header one
  -h, --help     show this help
]]

local function read_file(path)
  local fh, err = io.open(path, 'rb')
  if not fh then return nil, err end
  local text = fh:read('*a')
  fh:close()
  return text
end

local function shell_quote(s)
  return "'" .. gsub(s, "'", "'\\''") .. "'"
end

-- whether a shell command succeeded, as os.execute says it in each Lua
local function succeeds(command)
  local ok = os.execute(command)
  return ok == true or ok == 0
end

-- the year git says a file was added in, following renames
local function first_year(path)
  local p = io.popen('git log --follow --diff-filter=A --format=%ad --date=format:%Y -- '
    .. shell_quote(path) .. ' 2>/dev/null')
  local years = p:read('*a')
  p:close()
  return tonumber(match(years, '(%d+)%s*$'))
end

local function is_tracked(path)
  return succeeds('git ls-files --error-unmatch -- ' .. shell_quote(path) .. ' >/dev/null 2>&1')
end

-- Converts the files given by args (as in Lua's arg, from index 1), writing to the
-- given streams, which default to io's. Returns the exit status.
local function main(args, stdout, stderr)
  stdout, stderr = stdout or io.stdout, stderr or io.stderr
  local write, all_specs, copyright = false, false, false
  local files = {}
  for _, a in ipairs(args) do
    if a == '-h' or a == '--help' then
      stdout:write(HELP)
      return 0
    elseif a == '-w' or a == '--write' then
      write = true
    elseif a == '--spec' then
      all_specs = true
    elseif a == '--copyright' then
      copyright = true
    elseif match(a, '^%-') then
      stderr:write(format("howlscript-moon-convert: unknown option '%s'\n", a))
      return 1
    else
      files[#files + 1] = a
    end
  end
  if #files == 0 then
    stderr:write(HELP)
    return 1
  end

  local status = 0
  local year = tonumber(os.date('%Y'))
  for _, path in ipairs(files) do
    local src, err = read_file(path)
    if not src then
      stderr:write('howlscript-moon-convert: ', err, '\n')
      status = 1
    else
      local opts = { spec = all_specs or match(path, '_spec%.moon$') ~= nil }
      if copyright then
        opts.copyright = { year = year, first_year = first_year(path) or year }
      end
      local text, warnings = moon_convert.convert(src, opts)
      local out_path = gsub(path, '%.moon$', '') .. '.howl'
      if not text then
        stderr:write(path, ': ', warnings, '\n')
        status = 1
      else
        for _, w in ipairs(warnings) do
          stderr:write(format('%s:%d: warning: %s\n', path, w.line, w.message))
          status = 1
        end
        local lua, compile_err = howlscript.to_lua(text, { chunkname = '@' .. out_path })
        if not lua then
          stderr:write(compile_err, '\n')
          status = 1
        end
        if write then
          local fh = assert(io.open(out_path, 'wb'))
          fh:write(text)
          fh:close()
          if is_tracked(path) then
            succeeds('git rm -q -- ' .. shell_quote(path))
          else
            os.remove(path)
          end
        else
          if #files > 1 then stdout:write('-- ', path, '\n') end
          stdout:write(text)
        end
      end
    end
  end
  return status
end

return {
  main = main,
}
