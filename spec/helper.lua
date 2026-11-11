-- Copyright 2026 Nils Nordman
-- License: MIT (see LICENSE.md at the top-level directory of the distribution)

-- The busted helper, set in .busted: lets busted run _spec.howl files, and `require`
-- find .howl modules along package.path.

local howlscript = require('howlscript')

local searchers = package.searchers or package.loaders
table.insert(searchers, 2, function(name)
  local howl_path = (package.path .. ';'):gsub('%.lua;', '.howl;')
  local path, err = package.searchpath(name, howl_path)
  if not path then return err end
  return assert(howlscript.loadfile(path)), path
end)

-- A file loader, named by `loaders` in .busted. The Lua's lines match the source's,
-- so traces need no rewriting.
package.preload['busted.modules.files.howlscript'] = function()
  return {
    match = function(_, filename)
      return filename:match('%.howl$') ~= nil
    end,

    load = function(busted, filename)
      local f, err = howlscript.loadfile(filename)
      if not f then
        busted.publish({ 'error', 'file' }, { descriptor = 'file', name = filename }, nil, err, {})
      end
      return f, function(_, info)
        local index = info.traceback:find('\n%s*%[C]')
        info.traceback = info.traceback:sub(1, index)
        return info
      end
    end,
  }
end
