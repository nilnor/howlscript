-- Copyright 2026 Nils Nordman
-- License: MIT (see LICENSE.md at the top-level directory of the distribution)

-- The busted helper, set in .busted: lets busted run _spec.howl files, lets `require`
-- find .howl modules along package.path, and adds the specs' assertions.

local howlscript = require('howlscript')
local luassert = require('luassert')
local say = require('say')

howlscript.insert_loader()

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

-- assert.match(s, pattern), taking the string first, unlike luassert's own
local function match(_, args)
  local s, pattern = args[1], args[2]
  return type(s) == 'string' and s:match(pattern) ~= nil, { s, pattern, n = 2 }
end

say:set('assertion.match.positive', "Expected '%s' to match '%s'")
say:set('assertion.match.negative', "Expected '%s' not to match '%s'")
luassert:register('assertion', 'match', match, 'assertion.match.positive', 'assertion.match.negative')

-- assert.raises(pattern, f): calling f raises an error matching pattern
local function raises(_, args)
  local pattern, f = args[1], args[2]
  local ok, err = pcall(f)
  local raised = ok and '<no error>' or tostring(err)
  return not ok and raised:match(pattern) ~= nil, { pattern, raised, n = 2 }
end

say:set('assertion.raises.positive', "Expected an error matching '%s', got '%s'")
say:set('assertion.raises.negative', "Expected no error matching '%s', got '%s'")
luassert:register('assertion', 'raises', raises, 'assertion.raises.positive', 'assertion.raises.negative')
