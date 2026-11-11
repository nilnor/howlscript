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
  summary = 'A language compiling to Lua for LuaJIT, the successor to MoonScript for Howl',
  detailed = [[
Howlscript keeps what works in MoonScript, like indentation, implicit returns,
classes, comprehensions and `with`, and adds properties and inherited metamethods
to classes. Its classes have MoonScript's layout, so the two languages can extend
each other's classes during a migration.

It needs LuaJIT. The MoonScript converter, howlscript.convert, also needs lpeg and
MoonScript 0.5.0, which aren't dependencies of the rock.
]],
  homepage = 'https://github.com/nilnor/howlscript',
  license = 'MIT',
}

dependencies = {
  'lua == 5.1',
}

build = {
  type = 'builtin',
  modules = {
    howlscript = 'src/howlscript/init.lua',
    ['howlscript.compiler'] = 'src/howlscript/compiler.lua',
    ['howlscript.convert'] = 'src/howlscript/convert.lua',
    ['howlscript.emitter'] = 'src/howlscript/emitter.lua',
    ['howlscript.errors'] = 'src/howlscript/errors.lua',
    ['howlscript.lexer'] = 'src/howlscript/lexer.lua',
    ['howlscript.parser'] = 'src/howlscript/parser.lua',
    ['howlscript.scope'] = 'src/howlscript/scope.lua',
  },
}
