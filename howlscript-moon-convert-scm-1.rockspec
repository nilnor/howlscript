-- Copyright 2026 Nils Nordman
-- License: MIT (see LICENSE.md at the top-level directory of the distribution)

rockspec_format = '3.0'
package = 'howlscript-moon-convert'
version = 'scm-1'

source = {
  url = 'git+https://github.com/nilnor/howlscript.git',
  branch = 'main',
}

description = {
  summary = 'Converts MoonScript to Howlscript',
  detailed = [[
Converts MoonScript 0.5.0 source to Howlscript, keeping its comments and layout,
with the howlscript-moon-convert command or the howlscript.moon_convert module. What
it can't convert it warns about, or leaves for the Howlscript compiler to reject.
]],
  homepage = 'https://github.com/nilnor/howlscript',
  license = 'MIT',
}

dependencies = {
  'lua >= 5.1',
  'howlscript',
  'lpeg',
  'moonscript == 0.5.0',
}

build = {
  type = 'builtin',
  modules = {
    ['howlscript.moon_convert'] = 'src/howlscript/moon_convert/init.lua',
    ['howlscript.moon_convert.cli'] = 'src/howlscript/moon_convert/cli.lua',
  },
  install = {
    bin = {
      ['howlscript-moon-convert'] = 'bin/howlscript-moon-convert',
    },
  },
}
