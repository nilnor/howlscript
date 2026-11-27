+++
title = "Tables and destructuring"
description = "Table literals, keys, taking tables apart and building them with comprehensions."
weight = 40
+++

Howlscript's tables are Lua's tables, with the same indexing, length operator,
metatables and library. What changes is how you write them, how you take them apart
and how you build them from a loop. This chapter goes through the differences, and
each example's Lua tab shows the Lua it compiles to.

## Table literals

A table is written in braces, as in Lua, but a key takes a colon where Lua takes
`=`. Positional values and keyed entries can come in any order:

```howl
point = {x: 3, y: 4}
primes = {2, 3, 5, 7}
mixed = {'first', 'second', size: 2}

print(point.x + point.y)        -- 7
print(#mixed)                   -- 2
```

Written over several lines, a line break separates the entries as a comma does, and
a comma after the last entry is fine too. This manual puts commas between values, as
in Lua, and none around functions, whose bodies end at the end of their line or
block, so a table of methods reads like a list of definitions. That's mostly a
matter of taste: commas and line breaks can be mixed as you like. The exception is an
entry starting with `-` or `~` on a line of its own, such as a negative number, which
needs the comma: without it, the `-` could also be continuing the line before.

```howl
wolf = {
  name: 'Akela',
  age: 7,
  tags: {'leader', 'grey'}

  howl: =>
    "#{@name} howls"

  greet: (other) =>
    "#{@name} greets #{other}"
}

print(wolf:howl())              -- Akela howls
print(wolf:greet('Raksha'))     -- Akela greets Raksha
```

### Keys

- **Names:** `name: value` sets the key `'name'`, Lua's `name = value`. The colon
  needs a space after it, as `{a:b}` would be the method call `a:b`.
- **Keywords** work as keys, and as fields: `{end: 10}` and `range.end`, which Lua
  only allows as `{["end"] = 10}` and `range["end"]`.
- **Quoted keys:** a key that isn't a valid name, such as one with a dash or a
  space, is written as a string: `'Content-Type': value` is Lua's
  `['Content-Type'] = value`. A double-quoted key interpolates, so
  `"#{name}_count": 0` builds the key from `name`.
- **Any value:** `[expr]: value` sets a key computed by an expression, as in Lua.
- **Shorthand:** `:name` is short for `name: name`, which replaces Lua's habit of
  writing `{name = name, age = age}`.

```howl
range = {start: 1, end: 10}
print(range.end - range.start)          -- 9

headers = {'Content-Type': 'text/plain'}
print(headers['Content-Type'])          -- text/plain

kind = 'wolf'
counts = {"#{kind}_count": 3}
print(counts.wolf_count)                -- 3

n = 3
squares = {[n]: n * n, [n + 1]: (n + 1) * (n + 1)}
print(squares[4])                       -- 16

name, age = 'Akela', 7
pup = {:name, :age}
print("#{pup.name} is #{pup.age}")     -- Akela is 7
```

### Braces

A nested table needs its own braces. The only place a table can leave them out is
in the [named arguments](@/manual/functions.md#named-arguments) at the end of a call.
A `[` starting a value always starts a [comprehension](#comprehensions), so it can't
make a table either:

```howl
config = {window: width: 80}        -- error: wrap the value in {}; only a call's own arguments can leave out the braces
```

```howl
primes = [2, 3, 5]                  -- error: expected 'for' in a list comprehension; table literals use {}
```

A table literal can be indexed where it stands, which Lua only allows inside
parentheses, as in `({...})[i]`:

```howl
level = 2
label = {'low', 'medium', 'high'}[level]
print(label)                    -- medium
```

## Destructuring

A table literal on the left of `=` is a pattern, which takes the value on the right
apart. That replaces Lua's lists of fields read one by one, as in
`local concat, insert = table.concat, table.insert`:

```howl
{:concat, :insert} = table          -- concat = table.concat, insert = table.insert
```

Each entry of the pattern reads one value out of the table:

- **By key:** `:name` reads the field `name` into a local of that name, and
  `key: target` reads the field `key` into another name, or any other target.
  String and expression keys work as in literals.
- **By position:** a plain entry reads the next index, so `{first, second} = list`
  reads `list[1]` and `list[2]`.
- **Nested:** a target can be a pattern itself, taking apart the value read for it.

```howl
wolf = {name: 'Akela', age: 7, tags: {'leader', 'grey'}}

{:name, age: years} = wolf
print("#{name} is #{years}")    -- Akela is 7

{tags: {first_tag, second_tag}} = wolf
print(second_tag)               -- grey
```

A pattern can stand beside other targets, taking apart the value it gets. That suits
functions returning a table among other values:

```howl
fetch = ->
  200, {body: 'hello', size: 5}

status, {:body} = fetch()
print("#{status}: #{body}")     -- 200: hello
```

New names in a pattern are declared as locals, as in any assignment, and names
already declared are updated. Fields and indexes can be targets too:

```howl
pos = {x: 0, y: 0}
{x: pos.x, y: pos.y} = {x: 3, y: 4}
print("#{pos.x}, #{pos.y}")     -- 3, 4
```

The value is evaluated once, and each target reads its own path out of it, as the
Lua tab shows. A value missing from the table gives `nil`, but taking apart `nil`
itself is an error when it runs, as indexing `nil` is in Lua.
[More on destructuring](@/reference.md#destructuring).

### In loops

A loop variable can be a pattern, which takes each value apart. `for x in *list`
goes over the values of a list (see [Control flow](@/manual/control-flow.md)):

```howl
pack = {{name: 'Akela', age: 7}, {name: 'Raksha', age: 5}}

for {:name, :age} in *pack
  print("#{name} is #{age}")    -- Akela is 7, then Raksha is 5

for i, {:name} in ipairs(pack)
  print("#{i}. #{name}")        -- 1. Akela, then 2. Raksha
```

### Not in parameters

A parameter can't be a pattern. Take a plain parameter, and destructure it in the
body, where it reads as any other statement:

```howl
area = ({:w, :h}) ->            -- error: Howlscript has no destructured parameters; take a plain one and destructure it in the body, as in (p) -> {:x, :y} = p
  w * h
```

```howl
area = (size) ->
  {:w, :h} = size
  w * h

print(area({w: 4, h: 3}))       -- 12
```

## Comprehensions

In Lua, building a table from another takes a loop that adds to it, as in
`names[#names + 1] = wolf.name`. A comprehension writes that loop as an expression
giving the new table.

### Lists

`[expr for ...]` collects the values of `expr` into a list. The `for` can be any
loop: `for x in *list`, a numeric `for i = 1, n` or a generic `for k, v in pairs(t)`.
An `if` or `unless` after it skips values:

```howl
numbers = {3, -1, 4, -1, 5}

squares = [n * n for n in *numbers]         -- {9, 1, 16, 1, 25}
positive = [n for n in *numbers if n > 0]   -- {3, 4, 5}
evens = [i for i = 1, 10 unless i % 2 == 1] -- {2, 4, 6, 8, 10}

print(table.concat(positive, ', '))         -- 3, 4, 5
```

The loop variable can be a pattern, as in any `for`, and the list can be a slice of
one, as `*list[2,]` leaves out its first value
([slices](@/reference.md#loops)):

```howl
pack = {{name: 'Akela', age: 7}, {name: 'Raksha', age: 5}, {name: 'Grey', age: 2}}

names = [name for {:name} in *pack]         -- {'Akela', 'Raksha', 'Grey'}
rest = [wolf.name for wolf in *pack[2,]]    -- {'Raksha', 'Grey'}
```

### Tables

`{key, value for ...}` sets `key` to `value` for each round of the loop, which
makes lookup tables and indexes:

```howl
pack = {{name: 'Akela', age: 7}, {name: 'Raksha', age: 5}}

by_name = {wolf.name, wolf for wolf in *pack}
print(by_name.Raksha.age)                   -- 5

allowed = {ext, true for ext in *{'lua', 'howl'}}
print(allowed.howl)                         -- true
print(allowed.moon)                         -- nil
```

With a single expression, `{expr for ...}`, the expression gives both the key and
the value, as a function returning two values does:

```howl
lines = {'width=80', 'height=24'}
settings = {line:match('(%w+)=(%w+)') for line in *lines}
print(settings.height)                      -- 24
```

### One `for`, one filter

A comprehension takes a single `for` and at most one `if` or `unless`. Several
filters combine with `and`, and going over several lists takes nested loops:

```howl
cells = [{x, y} for x in *xs for y in *ys]  -- error: a comprehension takes a single 'for'; go over several with nested for loops
```

```howl
xs, ys = {1, 2}, {'a', 'b'}

cells = {}
for x in *xs
  for y in *ys
    cells[#cells + 1] = x .. y

print(table.concat(cells, ' '))             -- 1a 1b 2a 2b
```

### Where it's compiled

A comprehension assigned to a name, returned or ending a function compiles to a
loop in place, as the Lua tabs above show. Anywhere else, as in a call's argument, it
becomes a function called on the spot, which builds the table and returns it:

```howl
numbers = {3, -1, 4}
print(#[n for n in *numbers if n > 0])      -- 2
```

A comprehension's variables follow the
[no-shadowing rule](@/manual/functions.md#no-shadowing) of parameters, and a
comprehension used as a statement of its own, which would throw its table away, is
an error.

## Where next

The [reference](@/reference.md#values) has the exact rules for table literals,
[destructuring](@/reference.md#destructuring) and
[comprehensions](@/reference.md#comprehensions).
