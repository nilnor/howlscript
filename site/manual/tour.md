+++
title = "A tour of Howlscript"
description = "The whole language in a few minutes, one short example at a time."
weight = 20
+++

Howlscript has Lua's values, operators and standard library, so if you know some
Lua, what's new here is mostly how you write it. Each section shows one part of the
language, and links to the [reference](@/reference.md) for the details. In the
examples, a comment like `-- 12` gives what the line evaluates to or prints, and
the Lua tab shows the Lua an example compiles to, for Lua 5.4. It's laid out for
reading there: the compiler itself keeps each statement on its source line.

The bitwise operators and `//` of Lua 5.3 work on every Lua: where a Lua lacks them,
they compile to its bit library and `math.floor(a / b)`, at no cost (see
[Bitwise operators and floor division](@/reference.md#bitwise-operators-and-floor-division)).

## Layout

Blocks are indented, and a statement ends at the end of its line:

```howl
if ready
  print('go')       -- the if's body
print('done')       -- after the if
```

A statement continues on the next line when its line ends with an operator or a
comma. Inside braces and parentheses, line breaks separate the entries. Comments
start with `--`.

```howl
total = price +
  shipping
size = {
  width: 80
  height: 24
}
```

## Variables

The first assignment to a name declares a local, so there's no `local` to write.
Later assignments update it, also from inside functions:

```howl
count = 0               -- declares the local count

bump = ->
  count += 1            -- updates it

bump()
print(count)            -- 1
```

Besides `+=`, there are `-=`, `*=`, `/=`, `%=`, `^=`, `..=`, `or=` and `and=`, and
`++` and `--` add or subtract 1. A name first assigned inside a block is local to that
block, so to use it after the block, declare it before with `local`:

```howl
local label
if count == 1
  label = 'one'
else
  label = 'many'
print(label)            -- one
```

Assigning to a name that isn't a local declares one, so globals are set through
`_G`, as in `_G.DEBUG = true`. A typo can't create a global by accident.
[More on assignment and scope](@/reference.md#assignment-and-scope).

## Strings

Double-quoted strings put in the value of any expression in `#{}`:

```howl
name = 'Ada'
print("Hello, #{name}!")      -- Hello, Ada!
print("#{#name} letters")     -- 3 letters
print('#{name}')              -- #{name}, as single quotes don't interpolate
print("\#{name} is #{name}")  -- #{name} is Ada, as \# doesn't start one
query = [[
  SELECT name FROM users
]]
```

## Tables

Tables take braces. Keys are written `key: value`, and on separate lines the entries
need no commas, though this manual writes them between values, as Lua does:

```howl
point = {x: 1, y: 2}
colors = {'red', 'green', 'blue'}
config = {
  width: 80,
  title: 'Notes',
  'max-size': 1024
}
pos = {:x, :y}                -- short for {x: x, y: y}
```

A table on the left of `=` takes the value apart:

```howl
{:x, :y} = point              -- x = point.x, y = point.y
{first, second} = colors      -- first = colors[1], second = colors[2]
{:insert, :concat} = table    -- table.insert and table.concat
```

[More on tables](@/reference.md#values) and
[destructuring](@/reference.md#destructuring).

## Types

`type` works as in Lua, and `is_a` asks the same question with a type name on the
right, which can come from any expression:

```howl
print(type(7))              -- number
print(7 is_a 'number')      -- true
print('7' is_a 'number')    -- false
print({} is_a 'table')      -- true
print(nil is_a 'nil')       -- true

kind = 'string'
print('howl' is_a kind)     -- true
```

The names are Lua's: `nil`, `boolean`, `number`, `string`, `table`, `function`,
`thread` and `userdata`. LuaJIT has one more, `cdata`, the type of the values its FFI
library creates, so there `ffi.istype` is what tells C types apart. A name written
as a string, as in `7 is_a 'Number'`, must be one of these, or it's an error. `is_a`
takes a class as well, which tests class membership instead — see
[Classes](@/manual/classes.md#class-membership).

## Functions

`->` makes a function. Its body follows on the same line or, indented, on the lines
below, and when it ends in an expression, the function returns its value:

```howl
add = (a, b) ->
  a + b

greet = (name = 'world') ->
  "Hello, #{name}!"

swap = (a, b) ->
  b, a

classify = (n) ->
  kind = n % 2 == 0 and 'even' or 'odd'
  "#{n} is #{kind}"

log = (fmt, ...) ->
  print(fmt:format(...))

print(add(1, 2))        -- 3
print(greet())          -- Hello, world!
print(classify(7))      -- 7 is odd
a, b = swap(1, 2)       -- a is 2, b is 1
log('%d wolves', 12)    -- 12 wolves
```

- **Defaults** are used when an argument is `nil`, as `name` is above.
- **`...`** works as in Lua, as in `log`.

[More on functions](@/reference.md#functions).

## Calls

Calls take parentheses, touching the function. Methods are called with `:`:

```howl
words = 'howl at the moon'
print(words:upper())              -- HOWL AT THE MOON
print('%d wolves':format(12))     -- 12 wolves
```

Named arguments at the end of a call make up one table, so
`Window(title: 'Notes', width: 80)` is `Window({title: 'Notes', width: 80})`. A call
that's a statement of its own can leave out its parentheses, which reads well when
it takes a function block:

```howl
timer.after 1, ->
  print('a second later')
```

[More on calls](@/reference.md#calls).

## Control flow

```howl
local sign
if n > 0
  sign = 'positive'
elseif n == 0
  sign = 'zero'
else
  sign = 'negative'

unless done
  attempts += 1

local pace
switch gear
  when 1, 2
    pace = 'slow'
  when 3
    pace = 'steady'
  else
    pace = 'fast'
```

Loops are Lua's, plus `for x in *list` for the values of a list, and `continue`:

```howl
for i = 1, 3
  print(i)

for key, value in pairs(config)
  print(key, value)

for wolf in *pack
  continue if wolf.asleep
  print(wolf.name)

while busy()
  wait()
```

`if`, `unless` and `for` also work at the end of a statement:

```howl
print(message) if verbose
retry() unless done
print(wolf.name) for wolf in *pack if wolf.age > 5
```

`if`, `unless`, `switch` and loops are statements, which give no value. For a value
that depends on a condition, use `and` and `or`, as in
`label = n == 1 and 'item' or 'items'`.

That matters at the end of a function or a file, which returns the value of the
expression it ends in. One ending in an `if` or a `switch` instead returns only what
its branches return with `return`, as in Lua, so a call ending a branch is only
called:

```howl
sign = (n) ->
  if n < 0
    return -1
  return 1

report = (ok) ->
  if ok
    print('done')     -- called, not returned: report returns nothing
  else
    print('failed')
```

[More on control flow](@/reference.md#control-flow).

## Comprehensions

A comprehension builds a list, or a table, from a loop:

```howl
numbers = {3, -1, 4, -1, 5}
positive = [n for n in *numbers if n > 0]     -- {3, 4, 5}
squares = [n * n for n in *numbers]           -- {9, 1, 16, 1, 25}
seen = {n, true for n in *numbers}            -- 3, -1, 4 and 5 map to true
```

[More on comprehensions](@/reference.md#comprehensions).

## `with`

A `with` block works on one value: `.x` is its field `x`, and `:m()` calls its method
`m`. Assigned, it gives that value:

```howl
button = with Button('OK')
  .width = 80           -- button.width = 80
  :on('click', ->       -- button:on(...)
    print('clicked')
  )
```

## Classes

`=>` makes a method, which takes `self`. In one, `@x` is `self.x`:

```howl
class Animal
  new: (name) =>
    @name = name

  speak: =>
    "#{@name} makes a sound"

class Wolf extends Animal
  speak: =>
    super() .. ', a long howl'

  get loud: =>
    @speak():upper()

wolf = Wolf('Akela')
print(wolf:speak())     -- Akela makes a sound, a long howl
print(wolf.loud)        -- AKELA MAKES A SOUND, A LONG HOWL
```

`new` is the constructor, `super()` calls the parent's version of the method, and
`get loud:` makes a property, read as `wolf.loud`. A class gives its instances
metamethods with `meta`, which subclasses inherit:

```howl
class Vec
  new: (x, y) =>
    @x = x
    @y = y

  meta {
    __add: (other) =>
      Vec(@x + other.x, @y + other.y)

    __tostring: =>
      "(#{@x}, #{@y})"
  }

print(Vec(1, 2) + Vec(3, 4))   -- (4, 6)
```

[More on classes](@/reference.md#classes).

## Rules to know

Howlscript is strict in a few places, so that code reads one way and mistakes show
up when it compiles:

- **Only `with` blocks and comprehensions are expressions,** not `if`, `switch` or
  loops.
- **No shadowing:** a parameter or loop variable can't take the name of a local
  that's in sight, a common source of bugs. `_` is exempt.
- **Keys need a space** after their colon, as `{a:b}` would be a method call:
  `{a: b}`.
- **Calls touch their parentheses:** `f(x)`, not `f (x)`.

When code falls foul of one of these, the compile error says how to fix it:

```sh
$ howlscript compile -e "label = if n == 1 then 'item' else 'items'"
(eval):1:9: 'if' is a statement and gives no value; assign or return in its branches instead
  label = if n == 1 then 'item' else 'items'
          ^
```

## Where next

The [reference](@/reference.md) has the rest of the language, precisely, and
[Using it from Lua](@/manual/from-lua.md) how to fit Howlscript into a Lua program.
