+++
title = "About Howlscript"
description = "What Howlscript is, and where it comes from."
+++

## What it is

Howlscript is another way to write Lua: a language with a syntax of its own,
indentation-based and lighter than Lua's, with classes, comprehensions and string
interpolation. It compiles to plain Lua, for LuaJIT 2.1 and Lua 5.2 to 5.5, and uses
Lua's values, operators and libraries as they are. Lua and Howlscript modules use each
other freely, so it fits into a Lua project as a whole program or as a few modules.

It's free and open source, under the MIT license. The source is
[on GitHub](https://github.com/nilnor/howlscript).

## Where it comes from

Howlscript began in 2026 as part of [Howl](https://howl.io), a text editor built on
LuaJIT, and is named after it. Howl had been written in
[MoonScript](https://moonscript.org), Leaf Corcoran's language that compiles to Lua,
since 2012, and MoonScript is Howlscript's inspiration: indented blocks, `->` and
`=>` functions, `@` for `self`, classes, comprehensions and `with` blocks all come
from it.

Howlscript isn't a new version of MoonScript, though. Its compiler was written from
scratch, in plain Lua, and the language differs from MoonScript in many places.
Howl's code has since been converted to Howlscript, and Howlscript moved into a
project of its own, independent of the editor.

## Coming from MoonScript

If you know MoonScript, Howlscript will feel familiar. `howlscript-moon-convert`
converts MoonScript 0.5.0 code to Howlscript, keeping its comments and layout, and
[Converting MoonScript](@/converting.md) covers how to use it and every difference
between the two languages.
