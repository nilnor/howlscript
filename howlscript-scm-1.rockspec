-- Copyright 2026 Nils Nordman
-- License: MIT (see LICENSE.md at the top-level directory of the distribution)

rockspec_format = '3.0'
package = 'howlscript'
version = 'scm-1'

source = {
  url = 'git+https://github.com/nilnor/howlscript.git',
  branch = 'main',
}

description = {
  summary = 'An indentation-based language that compiles to Lua',
  detailed = [[
Howlscript has implicit returns, classes with properties and metamethods,
comprehensions and `with` blocks, and compiles to Lua that keeps every statement on
its source line. It runs on LuaJIT 2.1 and Lua 5.2 to 5.5, but not Lua 5.1. The
howlscript command compiles and runs it.
]],
  homepage = 'https://github.com/nilnor/howlscript',
  license = 'MIT',
}

-- LuaJIT counts as 5.1, so PUC Lua 5.1 can't be left out here
dependencies = {
  'lua >= 5.1',
}

-- lpeg and MoonScript are for the specs of the MoonScript converter, a rock of its
-- own (howlscript-moon-convert-scm-1.rockspec), which share the suite
test_dependencies = {
  'busted',
  'lpeg',
  'moonscript == 0.5.0',
}

test = {
  type = 'busted',
}

build = {
  type = 'builtin',
  modules = {
    howlscript = 'src/howlscript/init.lua',
    ['howlscript.cli'] = 'src/howlscript/cli.lua',
    ['howlscript.compiler'] = 'src/howlscript/compiler.lua',
    ['howlscript.emitter'] = 'src/howlscript/emitter.lua',
    ['howlscript.errors'] = 'src/howlscript/errors.lua',
    ['howlscript.lexer'] = 'src/howlscript/lexer.lua',
    ['howlscript.parser'] = 'src/howlscript/parser.lua',
    ['howlscript.runtime'] = 'src/howlscript/runtime.lua',
    ['howlscript.scope'] = 'src/howlscript/scope.lua',
    ['howlscript.targets'] = 'src/howlscript/targets.lua',
  },
  install = {
    bin = {
      howlscript = 'bin/howlscript',
    },
  },
}
