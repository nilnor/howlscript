+++
title = "Using it from Lua"
description = "The howlscript module: requiring, loading and compiling Howlscript in a Lua program."
weight = 70
+++

The Lua module `howlscript` compiles and loads Howlscript. It's what the `howlscript`
command uses too, and it's plain Lua, needing no other modules.

## Requiring Howlscript modules

The easiest way in is to let `require` find `.howl` modules:

```lua
local howlscript = require('howlscript')
howlscript.insert_loader()

local notes = require('notes')   -- finds notes.howl, compiling it as it loads
```

From then on, `require` looks for a Howlscript module along `package.howlpath`
before it looks for a Lua one. Unless it's set already, `package.howlpath` is set to
`package.path` with `.howl` in place of `.lua`, so `.howl` files go where `.lua`
files would. A module that doesn't compile is an error, as a Lua module with a syntax
error is.

`howlscript.remove_loader()` takes the loader out again. Each returns `false` when it
had nothing to do.

## Loading and running

These work like Lua's functions of the same names:

```lua
local f, err = howlscript.loadstring(source, '=name', env)
local f, err = howlscript.loadfile('path/file.howl', env)
howlscript.dofile('path/file.howl', ...)
```

- **`loadstring(source, chunkname, env)`** returns a function running `source`, or
  `nil` and the error. `chunkname` names it in error messages, as Lua's chunk names
  do: `'@path'` for a file, `'=name'` for anything else. `env`, when given, is the
  function's environment.
- **`loadfile(path, env)`** does the same for a file.
- **`dofile(path, ...)`** runs a file with the arguments given, and returns what it
  returns. It raises an error when the file can't be read or doesn't compile.

## Compiling to Lua

`to_lua` returns the Lua for some Howlscript:

```lua
local lua, err, details = howlscript.to_lua(source, { chunkname = '@file.howl' })
local lua = howlscript.to_lua(source, { target = 'portable' })
```

On failure it returns `nil`, the formatted error and the error as a table,
`{ line, col, len, message }`, for tools such as editors. Its options:

- **`chunkname`** names the source in error messages, as for `loadstring`.
- **`target`** names the Lua to compile for: `luajit`, `5.2`, `5.3`, `5.4`, `5.5`, or
  `portable` for Lua that loads on all of them. Without it, the Lua is for the Lua
  running the compiler. An unknown target is an error. The reference's
  [Lua versions](@/reference.md#lua-versions) has how the Lua differs between them.

## Errors

A compile error reads `file:line:col: message`, followed by the line it's on and a
caret under the spot:

```
shapes.howl:2:7: no space is allowed between a function and the '(' of its call, as in f(x)
  print (area(3, 4))
        ^
```

The column counts characters. In the table `to_lua` returns, `col` is a byte column
instead, and `len`, when known, the length in bytes of the token the error is about.

Errors when the code runs need no translating: every statement of the Lua starts on
the line it starts on in the Howlscript, so Lua's own messages and tracebacks give
the right `.howl` line.

## Generated names

Names starting with `__hs` are reserved for the compiler, which uses them in the Lua
it writes. Howlscript code can't use them.
