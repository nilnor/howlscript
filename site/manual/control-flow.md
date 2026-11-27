+++
title = "Control flow"
description = "Conditionals, switch, loops, with blocks and statement modifiers."
weight = 50
+++

Howlscript's control flow is Lua's: `if`, `while`, numeric and generic `for`, and
`break`, with Lua's truth, where only `nil` and `false` are false. What changes is
how blocks are written, and what's added: `unless`, `switch`, loops over lists,
`continue`, statement modifiers and `with` blocks. This chapter goes through the
differences, and each example's Lua tab shows the Lua it compiles to.

## Blocks

A block is made of the lines indented under its header, so there's no `then`, `do`
or `end` to write:

```howl
size = 12

if size > 10
  print('too large')    -- the if's body
  size = 10
print(size)             -- 10, after the if
```

Indentation can be spaces, tabs or both, but as editors show tabs at different
widths, the lines of a block and the lines around it must be indented alike: a
line indented with a tab, followed by one indented with spaces, is an error, as
which is deeper would depend on the tab width.

A body can also follow on the header's line, after `then` or `do`, as in
`if done then return` or `for i = 1, 3 do print(i)`. That's a matter of taste: this
manual puts bodies on lines of their own.

## Conditionals

### `if`

`elseif` and `else` line up with their `if`:

```howl
size = 12

local category
if size < 10
  category = 'small'
elseif size < 100
  category = 'medium'
else
  category = 'large'

print(category)         -- medium
```

`category` is declared before the `if`, as a name first assigned inside a block is
local to that block. Without the `local`, each branch would assign a local of its
own, and the `print` would read the global `category`
([more on visibility](@/reference.md#visibility)).

### `unless`

`unless c` is `if not c`, which reads better than a negated condition. It can have an
`else`, but no `elseif`:

```howl
attempts = 0
done = false

unless done
  attempts += 1

print(attempts)         -- 1
```

### No value

As in Lua, `if` and `unless` are statements, so they give no value, and using one as
a value is an error:

```howl
label = if n == 1 then 'item' else 'items'  -- error: 'if' is a statement and gives no value; assign or return in its branches instead
```

When neither value can be `false` or `nil`, Lua's `and` and `or` choose between them.
Otherwise assign in the branches, as with `category` above:

```howl
n = 1
label = n == 1 and 'item' or 'items'
print("#{n} #{label}")  -- 1 item
```

The same goes for an `if` ending a function, which returns only what its branches
return with `return` ([`if` at the end](@/manual/functions.md#if-at-the-end)). And
as in Lua, a condition can't assign: `if x = f()` is an error, which suggests
assigning before the `if`.

## `switch`

`switch` compares one value with several, replacing Lua's chain of
`elseif x == ...`:

```howl
gear = 3

local pace
switch gear
  when 1, 2
    pace = 'slow'
  when 3
    pace = 'steady'
  else
    pace = 'fast'

print(pace)             -- steady
```

- **Layout:** the `when` clauses are indented under the `switch` and line up, and so
  does the `else`, which runs when no clause matches.
- **Values:** a `when` can take several values, separated by commas, and matches when
  any of them does. They're any expressions, but not `or` and `and` after a literal,
  as in `when 1 or 2`: that's always `1`, so it's an error suggesting `when 1, 2`.
- **Matching:** each value is compared with `==`, with the `when` value on the left
  (`3 == gear`), and the first clause that matches runs. There's no falling through
  to the next one.
- **Once:** the value switched on is evaluated once, so it can be a call.

Like `if`, a `switch` is a statement. In a function, the clauses return with
`return`:

```howl
kind_of = (word) ->
  switch word
    when 'if', 'unless', 'switch'
      return 'conditional'
    when 'for', 'while'
      return 'loop'
  'other'

print(kind_of('while'))     -- loop
print(kind_of('with'))      -- other
```

## Loops

### Numeric and generic

The numeric and generic `for` work as in Lua:

```howl
for i = 10, 1, -3
  print(i)              -- 10, 7, 4, then 1

for key, value in pairs({x: 1})
  print(key, value)     -- x  1
```

A name that a loop updates, such as a total, needs a value before the loop:

```howl
total = 0
for n in *{1, 2, 3}
  total += n
print(total)            -- 6
```

Without one, the update would declare a new local in each iteration, starting from
the global of that name, so it's an error:

```howl
for n in *{1, 2, 3}
  count += 1            -- error: 'count' would be a new local of each iteration, gone after it; give it a value before the loop, which the loop then updates
```

### Over a list

Lua goes over the values of a list with `for _, v in ipairs(list)`. In Howlscript,
`for v in *list` does that, with a numeric loop from 1 to `#list`:

```howl
pack = {'Akela', 'Raksha', 'Grey'}

for name in *pack
  print(name)           -- Akela, Raksha, then Grey
```

- **One variable:** the loop gives the values only. For the index too, use a numeric
  loop or `ipairs`.
- **Once:** the list and its length are taken before the loop, so values added to the
  list in the body aren't visited.
- **Any expression** can follow the `*`, as in `for word in *{'one', 'two'}` or
  `for line in *read_lines(path)`.
- **Holes:** the loop goes by `#list`, so a list with `nil`s in it can give `nil`
  values, where `ipairs` stops at the first.
- **Patterns:** the loop variable can take each value apart
  ([in loops](@/manual/tables.md#in-loops)).

### Slices

A slice limits a loop over a list to part of it: `*list[start, stop, step]`, where
each part is optional. Negative values count from the end, as in Python: a start of
`-2` starts at the second value from the end, and a stop of `-1` stops one value
before it. Going backwards takes a negative step with both ends given, as in
`*t[-1, 1, -1]`. With `t = {10, 20, 30, 40, 50}`:

| Loop | Goes over |
|---|---|
| `for x in *t[2,]` | 20, 30, 40, 50 |
| `for x in *t[,,2]` | 10, 30, 50 |
| `for x in *t[1, -1]` | 10, 20, 30, 40 |
| `for x in *t[2, -2]` | 20, 30 |
| `for x in *t[-2,]` | 40, 50 |
| `for x in *t[-1, 1, -1]` | 50, 40, 30, 20, 10 |

```howl
args = {'run', 'file.howl', '--verbose'}

for arg in *args[2,]
  print(arg)            -- file.howl, then --verbose
```

Slices work in loops and [comprehensions](@/manual/tables.md#comprehensions) only.
They don't copy part of a table:

```howl
rest = args[2,]         -- error: slices can only be used in loops, as in 'for x in *t[2,]'
```

### `while`

`while` works as in Lua. There's no `repeat ... until`, so for a loop whose body runs
at least once, use `while true` and leave it with `break`:

```howl
n = 0
while true
  n += 1
  break if n * n > 50

print(n)                -- 8
```

### `continue`

Lua has no `continue`, and its usual stand-in is a `goto continue` to a label at the
end of the loop's body. Howlscript's `continue` goes on with the next round of the
loop, and compiles to just that, as the Lua tab shows:

```howl
for i = 1, 6
  continue if i % 2 == 1
  print(i)              -- 2, 4, then 6
```

### `goto`

`break` leaves only the loop it's in. To leave several at once, `goto` a label after
them, as in Lua:

```howl
grid = {{1, 2}, {3, 4}}

local found
for row in *grid
  for cell in *row
    if cell == 3
      found = cell
      goto done
::done::
print(found)            -- 3
```

A `goto` jumps to a label in its block or a block around it, in the same function.
As in Lua, it can't jump forward past the declaration of a local to a label that
has more code after it, so a name first assigned between them is an error, which
`local` before the `goto` avoids. The compiler checks this, along with the rest of
[Lua's rules](@/reference.md#goto-and-labels).

### Loop variables

A loop's body can assign its variables on every Lua, also in Lua 5.5, which makes
them constants. There, a loop that assigns one gets a hidden variable and a local
copy of it:

```howl
for i = 1, 3
  i *= 10
  print(i)              -- 10, 20, then 30
```

Loop variables follow the [no-shadowing rule](@/manual/functions.md#no-shadowing)
of parameters: a loop variable can't take the name of a local that's in sight.

```howl
name = 'Akela'
for name in *names      -- error: loop variable 'name' shadows the local declared on line 1; rename one of them
  print(name)
```

## Statement modifiers

A statement can end in `if`, `unless` or a `for`, which reads well for guards and
one-line loops. A `for` modifier can take an `if` or `unless` of its own, to skip
values:

```howl
verbose = true
items = {{name: 'map', visible: true}, {name: 'key', visible: false}}

print('starting') if verbose
print(item.name) for item in *items if item.visible     -- map
```

The modifier applies to the whole statement:

- **Guards:** `return x if c` returns only when `c` holds, and `break if c` leaves
  the loop only then, as in the `while` above.
- **Assignments:** `x = 1 if c` assigns only when `c` holds. Unlike an assignment
  in an `if` block, a new name is declared outside the condition, so it can be used
  after it, and is `nil` when the condition didn't hold.
- **Values:** a modified expression ending a function is returned when the condition
  holds, and nothing otherwise.
- **Loops:** a `for` modifier runs its statement as the loop's body, so it can't
  declare a name, which would be a new local of each iteration. Give the name a value
  before the loop: `total = 0`, then `total += item.size for item in *items`.

```howl
count = 3
label = 'many' if count > 1
print(label)            -- many

first = (t) ->
  t[1] if t

print(first({7}))       -- 7
print(first(nil))       -- an empty line, as first returns nothing
```

In a one-line function, the modifier belongs to the function's body, so in
`handler: (f) -> open(f) if f` the `if` is part of the function
([more on statement modifiers](@/reference.md#statement-modifiers)).

## `with`

Lua code often works on one value for several lines, repeating its name on each.
A `with` block names it once: in the block, `.x` is the value's field `x`, and
`:m()` calls its method `m`.

```howl
with io.tmpfile()
  :write('Howl')
  :seek('set')
  print(:read('*a'))    -- Howl
  :close()
```

- **Once:** the value is evaluated once, at the start of the block.
- **Anywhere in the block:** `.x` and `:m()` work in expressions, as in
  `print(:read('*a'))`, and in functions defined in the block.
- **Nested:** in a `with` inside another, they refer to the inner block's value.
- **As a value:** assigned, returned or ending a function, a `with` block gives its
  value. That makes it handy for building one.

```howl
make_counter = ->
  with {n: 0}
    .bump = ->
      .n += 1

counter = make_counter()
counter.bump()
counter.bump()
print(counter.n)        -- 2

window = {status_bar: {}}
with window
  .title = 'Notes'
  with .status_bar
    .text = 'Ready'     -- window.status_bar.text

print(window.status_bar.text)   -- Ready
```

A line starting with `.` or `:` is always a statement of a `with` block. So a chain
of method calls can't go on over several lines, as Lua allows by starting a line
with `:upper()`. Keep it on one line, or assign the steps.

## `do`

`do` runs its body in a scope of its own, as in Lua, so names first assigned in it
are gone after it:

```howl
do
  tmp = 5
  print(tmp)            -- 5

print(tmp)              -- nil, as this tmp is the global
```

## Statements and values

Only `with` blocks and comprehensions are expressions. `if`, `unless`, `switch`, `do`
and loops are statements, and using one as a value is an error. To collect values
from a loop, use a [comprehension](@/manual/tables.md#comprehensions):

```howl
names = for wolf in *pack   -- error: 'for' is a statement and gives no value; collect values with a comprehension, as in [x * 2 for x in *t]
  wolf.name
```

A `with` block or comprehension that's assigned, returned or ends a function compiles
in place. Anywhere else, as in a call's argument, it becomes a function called on the
spot. A `return`, `break` or `continue` in it would act on that function, so it's an
error:

```howl
show = (t) ->
  print(with t
    return if .hidden   -- error: 'return' can't be used here, as the expression it's in is compiled to a function; assign the expression to a variable first
    .shown = true
  )
```

The compiler also catches two kinds of statements that can't be meant:

- **Dead code:** a statement after `return`, `break` or `continue` in the same block
  is an error.
- **Unused values:** as in Lua, only calls can be statements, except at the end of a
  function or file, where the value is returned. Anywhere else, an expression that
  does nothing is an error, which catches `==` written for `=`:

```howl
total = 0
for i = 1, 3
  total == i            -- error: this expression does nothing; only calls can be statements
```

## Where next

The [reference](@/reference.md#control-flow) has the exact rules for
[conditionals](@/reference.md#conditionals), [loops](@/reference.md#loops),
[statement modifiers](@/reference.md#statement-modifiers) and
[`with`](@/reference.md#with).
