+++
title = "Getting started"
description = "Your first program, compiling it to Lua, and modules."
weight = 10
+++

This chapter assumes Howlscript is [installed](@/install.md), so that the
`howlscript` command runs in your terminal.

## Your first program

Save this as `hello.howl`:

```howl
greet = (name = 'world') -> "Hello, #{name}!"

print(greet())
print(greet('Howlscript'))
```

And run it:

```sh
$ howlscript run hello.howl
Hello, world!
Hello, Howlscript!
```

`greet` is a function taking `name`, which is `'world'` when it's left out. A
function returns the value of its last expression, here a string, in which `#{name}`
puts the value of `name`. Calls take parentheses, as in Lua.

## Compiling to Lua

`howlscript run` compiles the file as it loads it. `howlscript compile hello.howl`
writes the Lua to `hello.lua` instead, and `-p` prints it:

```sh
$ howlscript compile -p hello.howl
```

```lua
local greet; greet = function(name) if name == nil then name = 'world' end return "Hello, " .. tostring(name) .. "!" end

print(greet())
return print(greet('Howlscript'))
```

- **It's plain Lua,** which runs without Howlscript, so you can ship the `.lua`
  files.
- **Every statement is on its source line.** Line 3 of `hello.lua` is line 3 of
  `hello.howl`, so when something fails, the error and its traceback give the line
  to look at in your Howlscript.
- **The last statement is returned,** as a file returns the value of its last
  statement, like a function. That's how modules work, below.

The Lua is for the Lua running the compiler. To compile for another, name it with
`-t`: `luajit`, `5.2` to `5.5`, or `portable` for Lua that loads on all of them.
[The howlscript command](@/manual/command.md) has the details.

## Modules

A file is a module, as in Lua. As it returns the value of its last statement, a
module ends with a table of what it offers:

```howl
-- shapes.howl
area = (width, height) -> width * height
perimeter = (width, height) -> 2 * (width + height)

{:area, :perimeter}
```

`{:area, :perimeter}` is short for `{area: area, perimeter: perimeter}`. Another file
requires the module as it would a Lua one:

```howl
-- main.howl
shapes = require('shapes')

print(shapes.area(3, 4))        -- 12
print(shapes.perimeter(3, 4))   -- 14
```

```sh
$ howlscript run main.howl
12
14
```

`howlscript run` lets `require` find `.howl` modules where it finds Lua ones, and it
still finds Lua modules too.

## Using Howlscript from Lua

A Lua program can use Howlscript modules once it lets `require` find them:

```lua
require('howlscript').insert_loader()

local shapes = require('shapes')   -- compiles and loads shapes.howl
print(shapes.area(3, 4))           -- 12
```

[Using it from Lua](@/manual/from-lua.md) covers that and the rest of the module.

## Where next

- [A tour of Howlscript](@/manual/tour.md) shows the language in a few minutes.
- The [reference](@/reference.md) describes all of it, precisely.
- [Converting MoonScript](@/converting.md), when you have MoonScript code to bring
  along.
