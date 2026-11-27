+++
title = "Functions"
description = "Defining functions, returning values, parameters, methods and calls."
weight = 30
+++

Howlscript's functions are Lua's functions: closures, multiple return values, `...`
and tail calls all work as you know them. What changes is how you write them. This
chapter goes through the differences, and each example's Lua tab shows the Lua it
compiles to.

## Defining functions

`->` makes a function. Its parameters come before the arrow, and its body follows,
here indented on the lines below:

```howl
add = (a, b) ->
  a + b

describe = (n) ->
  kind = n % 2 == 0 and 'even' or 'odd'
  "#{n} is #{kind}"

ping = ->               -- no parameters
  print('ping')

noop = ->               -- no body: does nothing
```

A body can also follow the arrow on the same line, as in `-> a + b`. That's a matter
of taste: this manual puts bodies on lines of their own, which usually reads better,
and keeps one-liners for short functions passed to a call.

Assigning a function to a new name declares a local, as any assignment does, and the
local is declared before the function, so the function can call itself. That's
Lua's `local function add(a, b)`. Writing `local` in front, as in
`local fact = (n) -> ...`, is Lua's `local fact = function(n) ... end` instead: the
local is declared after the function, so a `fact` inside it is the global, and the
recursion fails when it runs. So recursive functions leave out `local`.

Functions that call each other need each other's names declared up front, as in Lua:

```howl
local is_even, is_odd

is_even = (n) ->
  n == 0 or is_odd(n - 1)

is_odd = (n) ->
  n != 0 and is_even(n - 1)

print(is_even(10))      -- true
```

A module's functions go in its table, either assigned to fields or written in the
table:

```howl
M = {}

M.open = (path) ->
  io.open(path, 'r')

shapes = {
  area: (w, h) ->
    w * h

  perimeter: (w, h) ->
    2 * (w + h)
}
```

## Returning values

Expressions have values and statements don't, as in Lua. A function ending in an
expression returns its value, so there's no `return` to write in most functions. One
ending in a list of expressions returns all their values, and one ending in any
other statement, such as an assignment, returns nothing:

```howl
double = (x) ->
  x * 2                 -- returns x * 2

min_max = (a, b) ->
  math.min(a, b), math.max(a, b)

store = (t, v) ->
  t.value = v           -- returns nothing

low, high = min_max(7, 3)       -- 3, 7
```

`return` works as in Lua, for leaving early, and as a statement modifier it makes a
guard. `return if c` returns nothing when `c` holds:

```howl
fact = (n) ->
  return 1 if n <= 1
  n * fact(n - 1)

greet = (name) ->
  return if name == nil
  print("Hello, #{name}")
```

### Calls at the end

A function ending in a call returns what the call returns. A body of `print('x')`
compiles to `return print('x')`, a tail call, where Lua's `function() print('x') end`
would return nothing. That's usually harmless, but it matters when the caller looks
at the result, as with a callback whose `true` means "handled". End such a function
with a bare `return`:

```howl
on_key = (key) ->
  log.debug(key)
  return              -- returns nothing, whatever log.debug returns
```

### `if` at the end

`if`, `unless`, `switch` and loops are statements, which give no value. So when one
of them ends a function, it doesn't return anything by itself, as in Lua: write
`return` where a value is meant to be returned. A call ending one of its branches is
only called, and a value there does nothing, which is an error:

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

broken = (n) ->
  if n < 0
    -1                -- error: this expression does nothing; only calls can be statements
```

For a value that depends on a condition, `and` and `or` often read best, as in a
body of `n < 0 and -1 or 1`. [More on returning](@/reference.md#returning).

## Parameters

### Defaults

A parameter can have a default, used when its argument is `nil`. That replaces Lua's
`width = width or 80`, without its trap: `false` is a value like any other, and
isn't replaced by the default.

```howl
connect = (host, port = 80, secure = true) ->
  "#{host}:#{port} #{secure}"

print(connect('example.org'))               -- example.org:80 true
print(connect('example.org', 443, false))   -- example.org:443 false
print(connect('example.org', nil, false))   -- example.org:80 false
```

The defaults are handled in the order the parameters are written, so a default can
use the parameters before it:

```howl
pad = (s, width = #s + 2, fill = ' ') ->
  s .. fill:rep(width - #s)

print("[#{pad('ab')}]")             -- [ab  ]
print("[#{pad('ab', 4, '-')}]")     -- [ab--]
```

### `...`

`...` works as in Lua: a function takes it as its last parameter, and only that
function can use it, not the functions inside it.

```howl
log = (fmt, ...) ->
  print(fmt:format(...))

count = (...) ->
  select('#', ...)

log('%d wolves', 12)        -- 12 wolves
print(count(1, nil, 3))     -- 3
```

### No shadowing

A parameter can't take the name of a local that's in sight where the function is
defined. In Lua, that silently hides the outer local, a common source of bugs; here
it's a compile error:

```howl
name = 'Ada'
greet = (name) ->   -- error: parameter 'name' shadows the local declared on line 1; rename one of them
  print(name)
```

`_` is exempt, for parameters you don't use, as in `(_, value) ->`.

## Methods

`=>` makes a method: a function taking `self` as its first parameter. In one, `@x`
is `self.x`, and `@m()` calls `self:m()`:

```howl
counter = {
  n: 0

  bump: (by = 1) =>
    @n += by

  reset: =>
    @n = 0
}

counter:bump()
counter:bump(10)
print(counter.n)        -- 11
```

That's Lua's `function counter:bump(by)`, and a method can be added to a table the
same way any function is:

```howl
counter.show = =>
  print("count: #{@n}")

counter:show()          -- count: 11
```

A function defined inside a method sees its `self`, as a closure sees any local, so
`@` works there too. Outside a method, `@` is an error, as there's no `self`.

```howl
counter.bump_later = =>
  ->
    @bump()

later = counter:bump_later()
later()
print(counter.n)        -- 12
```

Classes, which build on methods, have [a chapter of their own](@/manual/classes.md).

## Calls

Calls look as they do in Lua, with a few rules that keep them unambiguous:

- **Parentheses touch the function:** `f(x)`. With a space, `f (x)` is an error.
- **String and table calls** work as in Lua: `require'lpeg'`, `Point {x: 1, y: 2}`.
- **Methods are called with `:`,** touching both sides: `file:read('*a')`. Literals
  can be receivers without Lua's parentheses: `'%d wolves':format(12)`.
- **No method references:** `obj:m` without a call is an error. Wrap it in a
  function that calls it, as in `(...) -> obj:m(...)`.

### Named arguments

Lua functions often take a table of options, called as `f{title = 'Notes'}`. In
Howlscript, `key: value` arguments at the end of a call make up that table:

```howl
open_window = (opts) ->
  "#{opts.title}, #{opts.width} wide"

print(open_window(title: 'Notes', width: 80))   -- Notes, 80 wide
```

The call is `open_window({title = 'Notes', width = 80})` in Lua. Positional
arguments come first, so `f(a, key: 1)` is `f(a, {key = 1})`.
[More on named arguments](@/reference.md#named-arguments).

### Passing functions

A function is passed like any other argument. Written on one line, it ends at the
next comma, so more arguments can follow it:

```howl
people = {{name: 'Ada', age: 36}, {name: 'Alan', age: 41}}
table.sort(people, (a, b) -> a.age > b.age)
print(people[1].name)   -- Alan

ok, err = pcall((path) -> assert(io.open(path)), 'missing.txt')
print(ok)               -- false
```

A body of several lines is indented under the call, and the call goes on after it,
on a line at the call's own indentation, with its closing parenthesis or more
arguments. The parenthesis can also end the body's last line.

```howl
ok, err = pcall(->
  file = assert(io.open('missing.txt'))
  file:read('*a')
)

ok, err = pcall((path) ->
  file = assert(io.open(path))
  file:read('*a')
, 'missing.txt')
```

### Calls without parentheses

A call that's a statement of its own can leave out its parentheses. That reads best
when its last argument is a function block, as with test frameworks and event
handlers:

```howl
describe 'stack', ->
  it 'starts empty', ->
    assert.equal 0, #Stack()
```

Only that call can do it: calls in its arguments, and calls whose value is used,
need their parentheses, so it's always clear which arguments go with which call.
[More on calls without parentheses](@/reference.md#calls-without-parentheses).

## Where next

The [reference](@/reference.md#functions) has the exact rules for functions,
[returning](@/reference.md#returning) and [calls](@/reference.md#calls).
