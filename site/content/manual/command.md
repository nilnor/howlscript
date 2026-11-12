+++
title = "The howlscript command"
description = "Compiling and running Howlscript from the terminal."
weight = 80
+++

The `howlscript` command compiles and runs Howlscript. It has two commands, `compile`
and `run`, and `howlscript help <command>` lists a command's options.

## Compiling

```sh
howlscript compile file.howl              # writes file.lua next to it
howlscript compile src/*.howl             # each file.howl to its file.lua
howlscript compile -p file.howl           # prints the Lua instead
howlscript compile -o out.lua file.howl   # writes it to out.lua
howlscript compile -e 'f = (a) -> a + 1'  # prints the Lua for a snippet
howlscript compile < file.howl            # reads stdin, printing the Lua
```

- **`-p`, `--print`** prints the Lua instead of writing files. With several inputs,
  a comment line naming each comes before its Lua.
- **`-o`, `--output <file>`** writes the Lua to `<file>`, for a single input.
- **`-e`, `--eval <code>`** compiles the code given, printing its Lua. Stdin, given as
  `-` or by giving no inputs at all, is printed too.
- **`-t`, `--target <lua>`** compiles for another Lua than the one running the
  command: `luajit`, `5.2`, `5.3`, `5.4`, `5.5`, or `portable` for Lua that loads on
  all of them.

It exits with 1 if an input doesn't compile, after printing the error, so it doubles
as a syntax check.

## Which Lua the Lua is for

Howlscript adapts the Lua it writes to the Lua it runs on, where Luas differ in ways
that would change what the code means. So by default, the compiled Lua is for the
Lua running `howlscript`, and may not load on another. When the Lua will run
elsewhere, name it with `-t`:

```sh
howlscript compile -t luajit plugin.howl     # for LuaJIT, whichever Lua compiles it
howlscript compile -t portable lib.howl      # for any of them
```

The reference's [Lua versions](@/reference.md#lua-versions) has the differences.

## Running

```sh
howlscript run script.howl arg1 arg2     # runs a file
howlscript run -e 'print(1 + 2)'         # runs a snippet
howlscript run - < script.howl           # runs stdin
```

The arguments are in `arg`, with the file in `arg[0]`, and are passed as `...`, as
the `lua` command passes them. The script can `require` `.howl` modules as well as
Lua ones. An error when it runs is printed with its traceback, and makes the command
exit with 1.
