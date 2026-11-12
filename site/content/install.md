+++
title = "Install Howlscript"
description = "Howlscript installs with LuaRocks, and needs nothing else but a Lua."
+++

## What you need

- **A Lua:** LuaJIT 2.1, or Lua 5.2, 5.3, 5.4 or 5.5. Lua 5.1 isn't supported, as
  Howlscript's `continue` needs Lua's `goto`.
- **[LuaRocks](https://luarocks.org),** Lua's package manager, to install it.

Howlscript itself is plain Lua, so there's nothing to build.

## With LuaRocks

Howlscript isn't on luarocks.org yet, but LuaRocks can install it straight from its
rockspec on GitHub:

```sh
luarocks install \
  https://raw.githubusercontent.com/nilnor/howlscript/main/howlscript-scm-1.rockspec
```

That installs the `howlscript` command and the Lua module `howlscript`. The command
runs on the Lua that your LuaRocks is set up for. Add `--local` to install it for
your user only, without administrator rights.

> **Command not found?** LuaRocks puts commands in its own `bin` directory, which
> for a `--local` install is `~/.luarocks/bin`. `eval "$(luarocks path --bin)"`
> adds it to your `PATH` for the current shell, and adds LuaRocks' modules to Lua's
> search paths too. Put it in your shell's startup file to keep it.

## From a checkout

To follow the latest changes, or to work on Howlscript, install it from a clone of
its repository:

```sh
git clone https://github.com/nilnor/howlscript.git
cd howlscript
luarocks make howlscript-scm-1.rockspec
```

Run `luarocks make` again after pulling to update it.

## Check that it works

```sh
howlscript compile -e 'greet = (name) -> "Hello, #{name}!"'
```

That should print the Lua for the snippet:

```lua
local greet; greet = function(name) return "Hello, " .. tostring(name) .. "!" end
```

`howlscript help` lists what else the command can do.

## The MoonScript converter

To convert MoonScript code to Howlscript, install `howlscript-moon-convert`, a rock
of its own as it needs MoonScript 0.5.0 and lpeg (which LuaRocks compiles, so it
needs a C compiler). Install Howlscript first, as above, and then:

```sh
luarocks install \
  https://raw.githubusercontent.com/nilnor/howlscript/main/howlscript-moon-convert-scm-1.rockspec
```

From a checkout, that's `luarocks make howlscript-moon-convert-scm-1.rockspec`.
[Converting MoonScript](@/converting.md) explains how to use it.

## Editor support

Editor plugins for Howlscript are still to come; the
[manual's chapter on editors](@/manual/editors.md) will list them. Until then, an
editor's MoonScript highlighting comes close for `.howl` files.

## Next steps

You're ready to write some Howlscript: [Getting started](@/manual/getting-started.md)
takes you through your first program.
