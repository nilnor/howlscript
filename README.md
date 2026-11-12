# Howlscript

Howlscript is an indentation-based language that compiles to Lua. It has implicit
returns, classes with properties and inherited metamethods, comprehensions and
`with` blocks, and it keeps things explicit: methods are called with `:`, calls
inside expressions take parentheses, tables take braces, and only `with` blocks and
comprehensions are values.

It runs on LuaJIT 2.1 and Lua 5.2 to 5.5. The compiler, the module `howlscript` in
`src/howlscript`, is plain Lua, with a hand-written lexer and a recursive-descent
parser. Howlscript files use the extension `.howl`.

```howl
class Note
  new: (path, tags = {}) =>
    @path = path
    @tags = tags

  get title: => @path:match('[^/]+$')

  tagged: (tag) => [t for t in *@tags if t == tag]

  save: (text) =>
    file = assert(io.open(@path, 'w'))
    file:write(text)
    file:close()

  meta {
    __tostring: => "Note(#{@title})"
  }

count = 0
count++
```

**[REFERENCE.md](REFERENCE.md) is the authoritative description of the language.**

## Installing

From a checkout, with LuaRocks:

```sh
luarocks make howlscript-scm-1.rockspec
```

That installs the module `howlscript` and the `howlscript` command.

## Compiling

```lua
local howlscript = require('howlscript')
-- on failure: nil, the formatted message, and { line, col, len, message }
local lua, err, details = howlscript.to_lua(source, { chunkname = '@file.howl' })
local lua = howlscript.to_lua(source, { target = 'portable' })
local f, err = howlscript.loadstring(source, '=name', env)
local f, err = howlscript.loadfile('path/file.howl', env)
howlscript.dofile('path/file.howl', ...)
howlscript.insert_loader()   -- from now on, require finds .howl modules too
```

**Targets:** the Lua is for the Lua running the compiler, unless `to_lua` is given a
`target`: `luajit`, `5.2`, `5.3`, `5.4`, `5.5`, or `portable` for Lua that loads on
all of them. An unknown target is an error. REFERENCE.md's Lua versions section
has how the Lua differs.

**Requiring Howlscript:** `insert_loader()` lets `require` load `.howl` modules, which
it then looks for along `package.howlpath` before it looks for Lua ones. Unless it's
set already, `package.howlpath` is set to `package.path` with `.howl` in place of
`.lua`. A module that doesn't compile is an error, as a Lua one with a syntax error
is. `remove_loader()` takes the loader out again. Each returns false when it had
nothing to do.

**Line alignment:** every statement of the Lua starts on the line where it starts
in the source. Code generated for a line already passed shares the current line. So
runtime errors and tracebacks point at the right `.howl` line without any line
mapping.

**Compile errors** are reported as `file:line:col: message`, followed by the source
line and a caret. The column counts characters. `to_lua` also returns the error as a
table, where `col` is a byte column and `len`, when known, the length in bytes of
the token the error is about.

**Generated names** start with `__hs`, a prefix reserved for the compiler.

## The howlscript command

```sh
howlscript compile file.howl            # writes file.lua next to it
howlscript compile -p file.howl         # prints the Lua instead
howlscript compile -e 'f = (a) -> a + 1'
howlscript compile -t 5.4 file.howl     # for Lua 5.4, whichever Lua runs it
howlscript run script.howl arg1 arg2    # can require .howl modules
howlscript help compile                 # a command's options
```

`compile` also reads stdin, writes to a file given with `-o`, compiles for the
target given with `-t` (`--target`), and doubles as a syntax check: it exits with 1
if an input doesn't compile. `run` runs a file, `-e` code or
stdin, with the arguments in `arg` and `...` as the `lua` command passes them.

## Converting MoonScript

`howlscript-moon-convert`, a rock of its own, converts MoonScript 0.5.0 to
Howlscript, keeping the source's comments and layout:

```sh
howlscript-moon-convert file.moon        # prints the Howlscript
howlscript-moon-convert -w src/*.moon    # writes each .howl in place of its .moon
```

[CONVERTING.md](CONVERTING.md) has its options, its Lua module, the rules it follows
and how the two languages differ.

## Developing

```sh
scripts/setup-lua                          # builds the Luas into .lua/, with LuaRocks and busted
scripts/run-specs                          # runs the specs under each of them
scripts/run-specs 5.4 spec/lexer_spec.howl # under one, for one file
```

`setup-lua` builds LuaJIT 2.1 and Lua 5.2 to 5.5, each with its own LuaRocks and the
rocks the specs need; it keeps what it built, so it can be run again after a failed
download. The specs are Howlscript, which busted runs through `spec/helper.lua`.
