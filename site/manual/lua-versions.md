+++
title = "Lua versions"
description = "What Howlscript does on LuaJIT and Lua 5.2 to 5.5, feature by feature."
weight = 85
+++

Howlscript compiles to Lua for LuaJIT 2.1 and Lua 5.2 to 5.5, and most of it
compiles to the same Lua for all of them. Where the Luas differ, Howlscript does one
of three things:

- **It writes the fastest form each Lua has,** as for the bitwise operators, which
  are operators on Lua 5.3 and later and library calls on the others.
- **It checks the feature itself,** as for `<const>`, which then works everywhere.
- **It reports an error** where a Lua can't have a feature at no cost, as for
  `<close>` before Lua 5.4.

Everything else, from numbers to the standard library, is the Lua's own, and differs
between Luas as it would in a Lua program.

## Which Lua the Lua is for

By default, Howlscript compiles for the Lua it runs on, so the Lua it writes may not
load on another. Bitwise operators compiled on Lua 5.4 stay operators, which Lua 5.2
rejects. With `mode = READ | WRITE` on line 2 of `flags.howl`:

```sh
$ howlscript compile flags.howl        # running on Lua 5.4
$ lua flags.lua                        # Lua 5.2
lua: flags.lua:2: unexpected symbol near '|'
```

When the Lua will run elsewhere, compile for it with `howlscript compile -t` (or
`to_lua`'s `target` option), naming one of these:

| Target | For |
|---|---|
| `luajit` | any LuaJIT 2.1 |
| `luajit-2026` | LuaJIT 2.1 built since July 2026, which has Lua 5.3's bitwise operators |
| `5.2`, `5.3`, `5.4`, `5.5` | that Lua |
| `portable` | Lua that loads on all of them |

This only matters for compiled `.lua` files. `howlscript run`, `require` with the
loader and `howlscript.loadstring` compile `.howl` source as they load it, for the
Lua they run on, so the same source works everywhere
([the command](@/manual/command.md#which-lua-the-lua-is-for) has more on `-t`).

## At a glance

| Feature | What each Lua gets |
|---|---|
| `&` `\|` `~` `<<` `>>` | the operators on Lua 5.3 and later and LuaJIT 2026; calls to `bit` on older LuaJIT, and to `bit32` on Lua 5.2; an error in portable Lua |
| `//` | the operator on Lua 5.3 and later; `math.floor(a / b)` on the others |
| `<const>` | checked by Howlscript on every Lua |
| `<close>` | Lua 5.4 and later; an error on the others |
| a loop assigning its variable | a hidden copy on Lua 5.5 and in portable Lua; as it is on the others |
| `\u{XXX}` escapes | decimal escapes on Lua 5.2 and in portable Lua; as they are on the others |
| `10LL`, `10ULL`, `2i` | LuaJIT; an error on the others |

The sections below go through each.

## Bitwise operators and floor division

Howlscript has Lua 5.3's bitwise operators, `&`, `|`, `~` (exclusive or, and
bitwise not as a unary), `<<` and `>>`, with their update forms `&=`, `|=`, `<<=`
and `>>=`, and floor division, `//` and `//=`:

```howl
READ, WRITE, EXEC = 1, 2, 4
mode = READ | WRITE
can_run = mode & EXEC != 0
middle = #lines // 2
```

Where a Lua has the operators, they stay as they are, as in the Lua tab above. Where
it doesn't, they become calls to its bit library, which LuaJIT's JIT compiles to the
same machine code as an operator. The functions are made locals on the first line,
only those used:

```lua
-- LuaJIT built before July 2026 (target luajit); Lua 5.2 has require('bit32')
local __hs_floor = math.floor
local __hs_band, __hs_bor = require('bit').band, require('bit').bor
local READ, WRITE, EXEC = 1, 2, 4
local mode = __hs_bor(READ, WRITE)
local can_run = __hs_band(mode, EXEC) ~= 0
local middle = __hs_floor(#lines / 2)
```

`//` is `math.floor(a / b)` on LuaJIT, which hasn't got it even when built since July
2026, and on Lua 5.2. Portable Lua takes that form of `//`, but has no form of the
bitwise operators that loads everywhere, so they're an error there:

```howl,no-lua
mode = READ | WRITE   -- error, in portable Lua: '|': portable Lua has no bitwise operators; ...
```

The results are each Lua's own, and they differ beyond small non-negative values:
LuaJIT works on signed 32-bit integers, Lua 5.2 on unsigned 32-bit ones, and Lua 5.3
and later on 64-bit integers, where a value without an integer representation is an
error:

| | LuaJIT | Lua 5.2 | Lua 5.3 and later |
|---|---|---|---|
| `12 & 5`, `12 \| 5`, `3 << 4` | 4, 13, 48 | 4, 13, 48 | 4, 13, 48 |
| `~5` | -6 | 4294967290 | -6 |
| `0x80000000 \| 0` | -2147483648 | 2147483648 | 2147483648 |
| `1 << 32` | 1 | 0 | 4294967296 |
| `-1 >> 28` | 15 | 15 | 68719476735 |
| `1.5 & 1` | 0 | 0 | error: number has no integer representation |
| `7.5 // 2` | 3 | 3 | 3.0 |

So code that runs on several Luas keeps to small non-negative values, as it would in
Lua.

## Constants and to-be-closed locals

A name being declared can take Lua 5.4's attributes, after it in the assignment that
declares it. `<const>` makes a constant, and Howlscript checks it, so it works on
every Lua, which gets a plain `local`:

```howl
MAX_ITEMS <const> = 100
```

Assigning `MAX_ITEMS` again, anywhere it's visible, is a compile error.

`<close>` makes a local whose value's `__close` metamethod runs when it goes out of
scope, however that happens: at the end of its block, by a `return` or `break`, or by
an error. That's cleanup that can't be skipped, as for a lock or a file:

```howl
class Lock
  new: (name) =>
    @name = name
    print("lock #{name}")

  release: =>
    print("unlock #{@name}")

  meta {
    __close: =>
      @release()
  }

save = (report) ->
  lock <close> = Lock('db')
  write(report)           -- if write fails, the lock is still released
```

Only Lua 5.4 and later have to-be-closed locals, and the other Luas can't have them at
no cost: each would need the rest of the block wrapped in a function called through
`pcall`. So `<close>` is a compile error for them, and code for them cleans up as Lua
code for them does, catching the error itself:

```howl
save = (report) ->
  lock = Lock('db')
  ok, err = pcall(write, report)
  lock:release()
  error(err, 0) unless ok
```

## Loop variables in Lua 5.5

Lua 5.5 makes the variables of a `for` loop constants, so assigning one there is an
error in Lua. In Howlscript it works on every Lua, which is handy for cleaning up a
value before using it:

```howl
for i, line in ipairs(lines)
  line = line:match('^%s*(.-)%s*$')
  print(i, line)
```

On Lua 5.5, and in portable Lua, a loop that assigns a variable gets a hidden one,
and the variable becomes a local copy of it. Loops that don't assign their variables
compile as they are:

```lua
-- Lua 5.5 and portable
for i, __hs_item1 in ipairs(lines) do
  local line = __hs_item1
  line = line:match('^%s*(.-)%s*$')
  print(i, line)
end
```

## Unicode escapes on Lua 5.2

Strings take `\u{XXX}` escapes on every Lua. Lua 5.2 lacks them, so there, and in
portable Lua, they become decimal escapes of the character's UTF-8 bytes:

```howl
greeting = "caf\u{e9}"     -- in Lua 5.2: "caf\195\169"
```

## LuaJIT's numbers

LuaJIT's FFI has numbers of its own: 64-bit integers, `10LL` and `10ULL`, and
imaginary numbers, `2i`. Howlscript takes them, but only when compiling for LuaJIT,
as the other Luas would reject them:

```howl,no-lua
big = 0x7fffffffffffffffLL
z = 2i
```

The bitwise operators take the 64-bit integers, as LuaJIT's own do, but `//` doesn't:
it's `math.floor(a / b)` on LuaJIT, and `math.floor` raises an error for them. Their
`/` already divides as integers, though rounding toward zero, so `-7LL / 2LL` is
`-3LL`.

FFI values have the type `cdata`, which `is_a` can test like any other type, as in
`x is_a 'cdata'`. That's false on the other Luas, which have no such values.

## What stays the Lua's own

Howlscript's values and library are those of the Lua it runs on, so everything below
differs between Luas just as in Lua code. The exact set depends a little on how a Lua
is built, as Lua's compatibility options bring some older functions back.

- **Integers and floats:** Lua 5.3 and later tell them apart, so `4 / 2` is `2.0`
  there, and `2` on LuaJIT and Lua 5.2. `math.type` tells them apart where they
  differ.
- **Library:** LuaJIT and Lua 5.2 have `unpack`, and Lua 5.2 and later
  `table.unpack`. Only LuaJIT has `setfenv`, so code for several Luas gives `load`
  an environment instead. `utf8`, `string.pack` and `math.type` are Lua 5.3's and
  later's. `bit` is LuaJIT's, and `bit32` Lua 5.2's.
- **Metamethods:** a class's `meta` takes every Lua's metamethods on every Lua, and
  a Lua ignores those it lacks. LuaJIT ignores `__gc` on tables, and `__len`,
  `__pairs` and `__ipairs` on tables unless it's built with Lua 5.2 compatibility.
  Lua 5.4 and later ignore `__ipairs`.

As in Lua, a name that differs between versions can be settled once, at the top of a
file:

```howl
unpack = table.unpack or unpack
```

[The reference's Lua versions](@/reference.md#lua-versions) has the same in brief.
