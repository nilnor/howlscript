# Converting MoonScript to Howlscript

`howlscript-moon-convert` converts MoonScript 0.5.0 to Howlscript, following the
rules below: what a converted file should look like. It parses with MoonScript's own
grammar, so it's a rock of its own (`howlscript-moon-convert-scm-1.rockspec`),
needing MoonScript 0.5.0 and lpeg, and it keeps the source's comments and layout.
What it can't decide is left as it is, for the Howlscript compiler to reject or with
a warning, and fixed by hand following the same rules (see [By hand](#by-hand)).
[Compared with MoonScript](#compared-with-moonscript) lists every difference between
the two languages.

## Using it

```sh
howlscript-moon-convert file.moon        # prints the Howlscript
howlscript-moon-convert -w src/*.moon    # writes each .howl in place of its .moon
howlscript-moon-convert --help
```

Warnings for what needs a look, and errors compiling the result, go to stderr, and
make it exit with 1. `-w` removes each `.moon`, with `git rm` when git tracks it.
`--spec` converts files as busted specs (see [Calls](#calls)), as it does any file
named `*_spec.moon`, and `--copyright` updates copyright headers (see
[Principles](#principles)).

From Lua:

```lua
local moon_convert = require('howlscript.moon_convert')
-- on failure: nil and the parse error
local text, warnings = moon_convert.convert(moonscript_source, { spec = true })
```

`warnings` lists `{ line, message }` for what needs a look. The `copyright` option,
as in `{ year = 2026, first_year = 2014 }`, does what `--copyright` does, with
`first_year` the year the file was added.

## Principles

- **Mechanical:** a conversion changes only what Howlscript requires, so it reads
  line by line against the original. Improvements, like `x = x or {}` to `x or= {}`,
  are separate changes.
- **Odd spacing is fixed,** as two spaces where one belongs (`new:  =>`, `->  x`,
  `x  = 1`), a space before a comma or none after it, a block indented by other
  than two spaces, a closing brace on a line of its own not lined up with the line
  its table opens on, trailing whitespace, or `for _=1,n` for `for _ = 1, n`.
  Spacing inside strings stays, and so do the lines of a long string in a block
  that moves.
- **Bugs found on the way** are fixed in the conversion and named in its commit, as
  an `assert.is_nil, x` would be: a value list, not a call, so it asserts nothing.
- **In place:** the `.howl` file replaces the `.moon` file of the same name, which
  `require` then finds instead, with Howlscript's loader in place (see
  [README.md](README.md)).
- **Copyright:** with `--copyright`, the years of Nils Nordman's copyright lines end
  with the year of the conversion, so `2012-2015` becomes `2012-2026`, and `2018`
  becomes `2018-2026`. A file without a copyright header gets the usual two-line
  one, starting from the year its original was added
  (`git log --follow --diff-filter=A`), or from this year outside git.

## Rules

### Imports

`import a, b from t` becomes `{:a, :b} = t`.

### Globals

Howlscript has no `export`, so assigning to a name always declares a local unless one
is visible:

- **Real globals** are set through `_G`: `export with_tmpdir = (f) -> ...` becomes
  `_G.with_tmpdir = (f) -> ...`. A run of them goes in a `with _G` block, as for a
  module table below. A name that `export *` made global only because it was in its
  scope, and that nothing else uses, becomes a local instead.
- **Writing a global through the function's environment,** as code run with an
  environment of its own may, can't be written in Howlscript, since `_G.x` bypasses
  the environment. Code that needs it stays Lua.
- **A module that `setfenv`s to its own table and exports into it** drops the
  `setfenv`, and every exported name becomes a field of the table wherever it's
  defined, read or written, also in nested functions and when the module calls its
  own functions. A run of definitions goes in a `with` block on the table, where
  `.name` reaches the fields in nested functions too. A table called `_ENV` gets the
  module's name:

  ```moonscript
  _ENV = {}
  setfenv 1, _ENV
  export delete, change
  export reset = ->
    delete = false
  export execute = (f) ->
    reset!
  return _ENV
  ```

  ```howl
  state = {}
  with state
    .reset = ->
      .delete = false
    .execute = (f) ->
      .reset()
  return state
  ```

  Inside another `with` in such a block, `.name` is the inner target's, so the
  module's fields are written out there (`state.delete`). A local with the table's
  name would update the table instead of declaring a local, so it gets renamed.

  A `setfenv` that gives other code an environment stays, as one running
  definitions with a table of their own as their environment does.

### Calls

- `obj\m args` becomes `obj:m(args)`, and `f!` becomes `f()`.
- **Parentheses:** every call gets them, in specs too, except:
  - a call taking a function block;
  - a call whose only argument is a table;
  - in specs, statements calling busted's `describe`, `context`, `it`,
    `before_each`, `after_each`, `setup`, `teardown` and `pending`, and assertions
    (`assert.equal 'x', buffer.text`). A spec's own helpers get parentheses, as in
    `check_lines({...}, m:structure(text))`.

  ```moonscript
  table.insert clips, 1, item
  error "Unknown event '#{name}'", 2 unless all[name]
  file\read_async (res) ->
    ...
  settings.define {
    name: 'max_items'
  }
  ```

  ```howl
  table.insert(clips, 1, item)
  error("Unknown event '#{name}'", 2) unless all[name]
  file:read_async (res) ->
    ...
  settings.define {
    name: 'max_items'
  }
  ```

- **Calls in other calls' arguments and calls used as values** get parentheses
  everywhere, also in the arguments of a spec call and in inline functions there, in
  block headers and in interpolations:

  ```moonscript
  assert.raises 'none', -> events.connect 'none', -> true
  for handler in *handlers_for name
  co = coroutine.create (...) -> handler ...
  if first\match '%p'
  "Context<#{tostring @buffer}>"
  ```

  ```howl
  assert.raises 'none', -> events.connect('none', -> true)
  for handler in *handlers_for(name)
  co = coroutine.create((...) -> handler(...))
  if first:match('%p')
  "Context<#{tostring(@buffer)}>"
  ```

- **A function block in arguments or a `return`:** when a call with a function block
  is itself an argument, or gets a `return` (see [Control flow](#control-flow)), the
  parentheses close on a line of their own after the block:

  ```moonscript
  file\read_async async (res) ->
    assert.equals 'text', file\read_finish(res)
    done!
  ```

  ```howl
  file:read_async(async((res) ->
    assert.equals 'text', file:read_finish(res)
    done()
  ))
  ```

- **A table as the only argument:** the call keeps its form anywhere, since
  Howlscript takes a table after a name as its only argument, as Lua does. Other
  arguments, a long string included, get parentheses as usual:

  ```moonscript
  primary = freeze {
    clear: -> selection\set_text ''
  }
  keyword = c 'keyword', word {
    'auto', 'break'
  }
  buffer.text = dedent [[
    int main() {}
  ]]
  ```

  ```howl
  primary = freeze {
    clear: -> selection:set_text('')
  }
  keyword = c('keyword', word {
    'auto', 'break'
  })
  buffer.text = dedent([[
    int main() {}
  ]])
  ```

- **A module ending in a call** gets `return` and parentheses, so its value stands
  out: `freeze Settings` becomes `return freeze(Settings)`. A call taking a function
  block keeps its form, as `lexer.build ->` does.

- **A comprehension as the first argument:** the call gets parentheses, since
  `f [x]` reads as an index: `assert.same [a for a in *t], b` becomes
  `assert.same([a for a in *t], b)`.
- **A space before parentheses:** MoonScript's `f (a)` passes `(a)`, while Howlscript
  rejects the space. When the parentheses hold all the arguments, the space goes:
  `Explorer (root .. 'sub/')` becomes `Explorer(root .. 'sub/')`. Around a call or
  `...` they stay, as they cut its values down to one: `f (g!)` becomes `f((g()))`.
  Otherwise the call gets parentheses of its own around them, and an assertion gets
  them too, since its argument can't start a call without them:

  ```moonscript
  Explorer (@root / item.path), @options!
  assert.is_nil ([b for b in *buffers when b.file == other])[1]
  ```

  ```howl
  Explorer((@root / item.path), @options())
  assert.is_nil(([b for b in *buffers if b.file == other])[1])
  ```

- **A negative first argument:** MoonScript's `f -1`, with a space before the `-`
  and none after it, calls `f(-1)`, where Howlscript subtracts. The call gets its
  parentheses as usual, so `s\sub -2` becomes `s:sub(-2)`. An assertion starting
  with one gets them too, since its argument can't start a call without them:
  `assert.equals -1, x` becomes `assert.equals(-1, x)`.

- **Named arguments before positional ones** get braces:
  `assert.same description: 'bar', x` becomes `assert.same {description: 'bar'}, x`.
- **Function stubs:** `obj\m` becomes `(...) -> obj:m(...)`, so `pcall obj\m, res`
  becomes `pcall((...) -> obj:m(...), res)`. A stub on self keeps its spelling:
  `@\m` becomes `(...) -> @m(...)`, and `self\m` becomes `(...) -> self:m(...)`.
- **Several values after an inline function** in arguments or a table: MoonScript
  takes them into its body, where a `,` ends the body in Howlscript. So the function
  gets parentheses: `spy.new -> 'r1', 'r2'` becomes `spy.new((-> 'r1', 'r2'))`. That
  can bring out mistakes: MoonScript reads `paths: -> {}, files: -> {}` as putting
  `files` in the body of `paths`.
- **Arguments on the lines after a call:** they're named, so they become a table,
  with its own braces. When they're the only arguments, the call takes just that
  table. After a positional argument, the table opens on the call's line and closes
  with `})`. Named arguments on the call's own line stay as they are, as in
  `push(text, sync: false)`.

  ```moonscript
  settings.define
    name: 'max_log_entries'
    default: 1000

  events.register 'log-trimmed',
    description: 'Fired right after the log is trimmed'
    parameters:
      size: 'The new number of entries in the log'
  ```

  ```howl
  settings.define {
    name: 'max_log_entries'
    default: 1000
  }

  events.register('log-trimmed', {
    description: 'Fired right after the log is trimmed'
    parameters: {
      size: 'The new number of entries in the log'
    }
  })
  ```

  MoonScript also takes such a table after an argument without a comma. After a
  string, the comma is added: `f 'a'` with `b: 1` below becomes `f('a', {`. After a
  name, MoonScript calls the name with the table, which stays so: `f a` with `b: 1`
  below becomes `f(a {`.

- **A table as the only argument of a call on anything but a name,** as an index,
  gets parentheses, as Howlscript only takes a table after a name as an argument:
  `callbacks[1]` with `a: 1` below becomes `callbacks[1]({`.

- **Positional arguments continued after a trailing `,`** keep their lines inside
  the parentheses, which close after the last one:

  ```moonscript
  handle.tag = C.add_idle C.PRIORITY_LOW,
    callback,
    nil
  ```

  ```howl
  handle.tag = C.add_idle(C.PRIORITY_LOW,
    callback,
    nil)
  ```

- **`with` lines:** `\m args` becomes `:m(args)`, as `\indent!` becomes `:indent()`.

### Tables

A table without braces gets them:

- `return :a, :b` becomes `return {:a, :b}`, and `x = a: 1` becomes `x = {a: 1}`.
- **A key touching its value,** as in `sort:not x` or `text:remaining_text`, gets a
  space after the `:`, since Howlscript reads `a:b` as a method call.
- **A table ending a function, below other statements,** gets braces with its
  entries on lines of their own:

  ```howl
  (_, _, on_update) ->
    notify = on_update
    {
      complete: -> completions
    }
  ```
- **A table nested under a key** gets braces with its entries on lines of their
  own, whether it was an indented block or on the key's line. So does the table
  around it: `ui.window = visible: true, status: [m]: method` becomes a table over
  four lines, holding one over three. Here is how nested tables look in a table
  that's already over several lines:

  ```moonscript
  text:
    set: (v) => ...
    get: => ...
  current: get: ->
    clips[1]
  clips: get: -> clips
  ```

  ```howl
  text: {
    set: (v) => ...
    get: => ...
  }
  current: {
    get: ->
      clips[1]
  }
  clips: {
    get: -> clips
  }
  ```

### Layout

A line continuing an expression is indented deeper than the line it continues, as
Howlscript requires, so a continuation at the same indentation moves in:

```moonscript
opening_p\test(l) or
closing_p\test(l)
```

```howl
opening_p:test(l) or
  closing_p:test(l)
```

A body after `then`, `do` or `else` on the same line, as in `if c then x = 1 else
x = 2` or `when 'nil' then append(out, 'null')`, moves to lines of its own. The
language allows it, but Howlscript's style puts bodies on lines of their own. So does
a body that MoonScript takes without `then`, as in `preview: => if c return {`. A
`then` ending the line before its block stays, as in `if async then`, and so do
statement modifiers (`x = 1 if c`).

```moonscript
if not index or index > #list + 1 then index = #list + 1
elseif index < 1 then index = 1
```

```howl
if not index or index > #list + 1
  index = #list + 1
elseif index < 1
  index = 1
```

A comment touching a name or `]` gets a space, as Howlscript reads the `--` as a
decrement there: `x--note` becomes `x --note`. Comment lines ending a block stay in it,
above the closing brackets added after it.

### Strings

A long string with a level becomes one without, `[==[text]==]` becoming
`[[text]]`, or a single-quoted string when its text contains `]]`, as
`[==[a]]b]==]` becomes `'a]]b'`.

### Control flow

- `else if c then x` becomes `elseif c then x`.
- A `when` filter in a comprehension or `for` modifier becomes `if`.
- **A simple `if` value becomes `and` and `or`,** wherever its value is used:
  assigned, returned, ending a function, or inside an expression, where it gets
  parentheses as an operand. That's an `if` or `unless` with an `else` and no
  `elseif`, each branch a single expression on one line, whose `then` value can't be
  false or nil, being a string, number, table or function literal, arithmetic or
  `true`. The `c and a or b` it becomes must fit in 100 columns, and the `if` must
  hold no comments. A condition with an `or` outside parentheses gets them, as does
  an `unless` condition after its `not`:

  ```moonscript
  text: if l.nr == last_nr then '·' else tostring l.nr
  x = if not a or b then 'y' else z
  ```

  ```howl
  text: l.nr == last_nr and '·' or tostring(l.nr)
  x = (not a or b) and 'y' or z
  ```

  Any other `if` value becomes an `if` statement, as below.

- **`if` as a value:** the names are declared before the `if`, and each branch
  assigns them. A field needs no declaration, and a branch already ending in an
  assignment keeps it, as MoonScript drops the outer one there:

  ```moonscript
  pfx_p, sfx_p = if first\match '%p'
    '%p+$', '^%p+'
  elseif first\match '%w'
    '%w+$', '^%w+'
  ```

  ```howl
  local pfx_p, sfx_p
  if first:match('%p')
    pfx_p, sfx_p = '%p+$', '^%p+'
  elseif first:match('%w')
    pfx_p, sfx_p = '%w+$', '^%w+'
  ```

  An `if` value on one line becomes an `if` statement over several lines too (see
  [Layout](#layout)):

  ```moonscript
  env = if options.env then copy options.env else {}
  ```

  ```howl
  local env
  if options.env
    env = copy(options.env)
  else
    env = {}
  ```

  An `if` value without `else` is `nil` when nothing matches, so the `if` statement
  gets an `else` assigning `nil`, unless the name is surely `nil` there already, as
  a `left` declared just before is:

  ```moonscript
  local left
  left = if before and before.y == current.y then before
  ```

  ```howl
  local left
  if before and before.y == current.y
    left = before
  ```

  Any other `if` value inside an expression, as a table entry, an argument or a list
  element, goes into a local declared just before the statement and assigned in each
  branch, and the expression uses the local. It's named after the key it fills, or
  what it's passed as, unless that's a visible local, as `text` is here:

  ```moonscript
  @view\redraw_text if text.is_empty then current_value else text
  @view\redraw_prompt if @item.display_path then @item\display_path! else nil
  ```

  ```howl
  local new_text
  if text.is_empty
    new_text = current_value
  else
    new_text = text
  @view:redraw_text(new_text)
  local prompt
  if @item.display_path
    prompt = @item:display_path()
  else
    prompt = nil
  @view:redraw_prompt(prompt)
  ```

  A returned `if` value becomes an `if` statement returning in each branch:

  ```moonscript
  return if is_table
    offsets
  else
    table.unpack offsets
  ```

  ```howl
  if is_table
    return offsets
  else
    return table.unpack(offsets)
  ```

- **`switch` as a value** becomes a statement assigning in each case, as `if` does,
  with its `when … then` bodies on lines of their own:

  ```moonscript
  absolute_path = switch @file.path
    when File.separator then @file.path .. text
    else @file.path .. File.separator .. text
  ```

  ```howl
  local absolute_path
  switch @file.path
    when File.separator
      absolute_path = @file.path .. text
    else
      absolute_path = @file.path .. File.separator .. text
  ```

- **A loop as a value** collects into a new local list, which is then returned or
  assigned, unless a comprehension can do it. A loop assigned to a new name collects
  straight into it, but one assigned to the list it goes over collects into a new
  one. The list's name mustn't be a visible local:

  ```moonscript
  return for i = 1, #paths
    path = paths[i]
    File root\join(path)
  ```

  ```howl
  result = {}
  for i = 1, #paths
    path = paths[i]
    result[#result + 1] = File(root:join(path))
  return result
  ```

- **A comprehension with two `for`s** becomes nested loops collecting into a new
  local list, as a loop as a value does. Used as an argument, it's collected before
  the statement:

  ```moonscript
  locations = to_locations [{ uri: d.uri, range: e.range } for d in *docs for e in *d.edits], root
  ```

  ```howl
  edit_locations = {}
  for d in *docs
    for e in *d.edits
      edit_locations[#edit_locations + 1] = { uri: d.uri, range: e.range }
  locations = to_locations(edit_locations, root)
  ```

- **An expression kept for its effect,** which Howlscript rejects as a statement that
  does nothing: a conditional call `a and f(...)` becomes `f(...) if a`, and a read
  that triggers a lazy computation is assigned to `_`, as `line.block` becomes
  `_ = line.block`. Ending a function, such an expression is its value, and stays.
  Other expressions that do nothing are mistakes, fixed as bugs found on the way.

- **A one-line function ending in a `for` modifier, inside a table or call
  arguments,** gets a block body: `put: (t) => rawset env, k, v for k,v in pairs t`
  becomes `put: (t) =>` with `rawset(env, k, v) for k,v in pairs(t)` on the next
  line. The one-line form compiles in keyed entries and call arguments, but not in
  `[ ]` or a table's positional entries, where it would be unclear.

- **A function ending in an `if`, `unless` or `switch`:** where one of its bodies
  ends in a value, a call or a `with` block, MoonScript returned that, so it gets a
  `return`, also in nested `if`s:

  ```moonscript
  after = (seconds, f, ...) ->
    if seconds != 0
      after_approximately seconds, f, ...
    else
      after_exactly seconds, f, ...
  ```

  ```howl
  after = (seconds, f, ...) ->
    if seconds != 0
      return after_approximately(seconds, f, ...)
    else
      return after_exactly(seconds, f, ...)
  ```

  A `with` block becomes `return with x`.

  Constructors are the exception. Nothing uses their values, so Howlscript compiles
  them without one, and their `if`s stay as they are.

### Parameters

Howlscript has no `@x` parameters. Each becomes a plain parameter, assigned to its
field at the top of the body, one line each, in the order of the parameters:

```moonscript
new: (@buffer, @pos) =>
show: (widget, @show_options = {position: 'center'}) =>
  error('Missing argument #1: widget', 2) if not widget
```

```howl
new: (buffer, pos) =>
  @buffer = buffer
  @pos = pos
show: (widget, show_options = {position: 'center'}) =>
  @show_options = show_options
  error('Missing argument #1: widget', 2) if not widget
```

### Names

- **Shadowing:** a parameter or loop variable that shadows a visible local gets
  another name, as `op = (editor) -> ...` inside a function with an `editor`
  parameter becomes `op = (ed) -> ...`. A parameter named `self` keeps its name, as
  `self` is exempt.
- **A local named like the module table** in a module that used `setfenv` gets a
  name for what it holds.

### Classes

- **Metamethods** go in the class's `meta`. Subclasses inherit them in Howlscript,
  where a MoonScript subclass didn't inherit metamethod members. It stands where the
  first of them stood, with its braces on lines of their own and an entry on each
  line:

  ```moonscript
  __tostring: => @text
  __len: => (@end_pos - @start_pos) + 1
  ```

  ```howl
  meta {
    __tostring: => @text
    __len: => (@end_pos - @start_pos) + 1
  }
  ```

- **An `__index` member** did nothing in MoonScript, as the base's `__index` replaced
  it, while in `meta` it's a fallback. The converter moves it there with a warning,
  to be dropped or kept by hand.
- **Members reading class-body locals:** MoonScript added a class's members before
  running its body, so a member reading a local the body assigns saw nil, where
  Howlscript, running the body top to bottom, sees the value assigned above it. The
  converter warns about such members.
- **A module ending in a class** stays as it is, as Howlscript returns a class ending
  a file, like MoonScript.
- **Members added to `__base` after the class** stay as they are, as instances find
  them, also in a class with properties: `File.__base.rm = File.delete` gives every
  file `rm`.

## By hand

The converter leaves these as they are, for the rules above to be applied by hand.
The Howlscript compiler rejects all but the warned ones, and `howlscript-moon-convert`
reports both:

- `export`, and `setfenv` modules (see [Globals](#globals));
- loops as values, warned about, and comprehensions with two `for`s;
- `if` values inside expressions not simple enough for `and` and `or`, and `switch`
  values inside expressions;
- expressions kept for their effect;
- parameters and loop variables shadowing a local;
- assignments in `if` and `with` headers.

## Compared with MoonScript

This compares Howlscript with MoonScript 0.5.0, which the converter reads.
[REFERENCE.md](REFERENCE.md) describes Howlscript itself.

### Changed

| MoonScript | Howlscript |
|---|---|
| `obj\method args` | `obj:method(args)`. Using `\` is an error. |
| `f!` | `f()`. `!` is an error; negate with `not`. |
| `print sum 10, 20`, `x = f a` | `print sum(10, 20)`, `x = f(a)`. Only a call that is a statement of its own can leave out its parentheses, and only one per line (see [Calls without parentheses](REFERENCE.md#calls-without-parentheses)). A call whose only argument is a table needs none anywhere, as in Lua. |
| `f (a)` passes `(a)` | An error: the `(` must touch the function. `f (x) -> x` still passes a function. |
| `x -1` calls `x(-1)` | A subtraction. |
| Arguments continued on indented lines, nested by indentation | Inside parentheses, where line breaks are free. Without parentheses, arguments only continue after a trailing `,` and can't nest. |
| An inline body in arguments or a table takes the rest of the line: `f(-> a, b)` passes one function returning `a` and `b` | A `,` ends it there, so `f(-> a, b)` passes a function returning `a`, and `b`. `f((-> a, b))` passes one function returning both (see [Layout](REFERENCE.md#layout)). |
| `f a: 1, 2` | An error: positional arguments come first. |
| `x = a: 1`, `return a: 1`, indented key blocks | `x = {a: 1}`. A table needs braces, except for the trailing named arguments of a call. |
| A member named after a metamethod, as in `__tostring: => @x`, is one, since the base is the instances' metatable | An error: metamethods go in `meta {...}`. |
| A subclass doesn't inherit its parent's metamethods | It does. |
| An `__index` member is ignored, as the base's `__index` is set to the base afterwards | `__index` and `__newindex` in `meta` are fallbacks for keys the instance doesn't have (see [Metamethods](REFERENCE.md#metamethods)). |
| `f[[text]]` calls `f` | An error: write `f([[text]])`, or `f [[text]]` in a statement. |
| `x = f {a}, b` passes `{a}` and `b` to `f` | Passes only the table, as in Lua: `x = f({a}), b`. Only at the start of a statement does `f {a}, b` pass both. |
| `x--note` is a comment | A decrement followed by `note`. Write `x -- note`. |
| `unless a ... elseif b` | `unless` takes an `else` but no `elseif`. |
| `if`, `unless` and `switch` are values: `label = if n == 1 then 'item' else 'items'`, `return if c then a else b` | Statements without a value, so using one as a value is an error. Assign or return in the branches. |
| A function ending in an `if`, `unless`, `switch` or `do` returns the value its body ends with | It returns only what the body returns with `return`; a value or a call ending a branch is an error. A statement modifier at the end, as in `-> f(x) if x`, still passes on its value. |
| Loops are values: `doubled = for x in *t` collects a list | Statements without a value; collect with a comprehension. |
| Comprehensions and `for` modifiers filter with `when`: `[x for x in *t when x > 0]` | With `if` or `unless`: `[x for x in *t if x > 0]`. `when` there is an error; it only starts the cases of a `switch`. |
| A comprehension takes several `for` and `when` clauses: `[{x, y} for x in *xs for y in *ys]` | A single `for`, with at most one filter. Nest `for` loops instead, and combine conditions with `and`. |
| `x = do ...` gives the value of the block's last statement | An error: a `do` block is a statement. |
| Parameters and loop variables can shadow locals | An error; rename one of them (see [Scope](REFERENCE.md#scope)). |
| A class body adds all its members before running its other statements | It runs top to bottom (see [Classes](REFERENCE.md#classes)). |
| `goto` can be a variable name | An error, like the other Lua keywords Howlscript doesn't use. |
| `import`, `from`, `using` and `extends` are reserved | They're ordinary names; `extends` only means something after a class name. |

These MoonScript 0.5.0 bugs are fixed:

- **Update operators:** `t[f()] += 1` and `f().n += 1` call `f` twice. Howlscript
  calls it once.
- **Destructuring among other targets:** in `a, {:b}, c = f()`, `b` and `c` get nil.
  In Howlscript, `b` is read from `f`'s second value, and `c` is its third value.
- **Lua keywords as method names:** `obj\end!` and `@end` compile to invalid Lua.

Howlscript also reports mistakes that MoonScript 0.5.0 compiles without complaint:

- **Useless expressions:** an expression statement that does nothing, like `x` or
  `a == b`, where MoonScript writes `local _ = x`.
- **Dead code:** code after `return`, `break` or `continue` in the same block.
- **Jumps out of a value block:** `return`, `break` or `continue` in a value block
  that's compiled to a function, where MoonScript returns from the function it
  generates.
- **`...`:** using `...` in a function that doesn't take it.
- **`self`:** using `@` or `@@` with no `self` around.
- **`super`:** using `super` outside a class method, or in a class without a parent.

### Left out

| MoonScript | Instead |
|---|---|
| `import a, b from t` | `{:a, :b} = t`. Destructuring shows how the names get into scope. |
| `import \m from obj` | `m = (...) -> obj:m(...)` |
| `obj\method` (a function stub) | `(...) -> obj:method(...)`. Stubs hide references and keep objects alive. |
| `(a using b) ->`, `(using nil) ->` | Parameters can't shadow locals, and `local x` declares a fresh local where one is needed. |
| `local *`, `local ^` | `local a, b`, naming each. |
| `(@x) =>` and `(@@x) =>`, setting `self.x` or `self.__class.x` from a parameter | A plain parameter, assigned in the body: `(x) => @x = x`, or `@@x = x`. |
| `export x = v`, `export x`, `export *`, `export ^`, `export class Foo` | `_G.x = v`. Assigning to a name that isn't a visible local always declares a local, so globals are only set through `_G` (see [Globals](REFERENCE.md#globals)). `export` is an ordinary name. |
| `x = class ...`, `class extends Base` (class expressions and anonymous classes) | A named class statement, then `x = Name`. |
| `class a.B` | `class B`, then `a.B = B`. |
| `if x = f()`, `elseif x = f()` | `x = f()` before the `if`. For `elseif`, nest an `if` in the `else`. |
| `with x = f()` | `x = f()`, then `with x`. |
| `&`, `\|`, `~`, `<<`, `>>`, `//` and `&=`, `\|=`, `<<=`, `>>=` | A bitwise library, such as LuaJIT's `bit` (`bit.band(a, b)`), and `math.floor(a / b)`. MoonScript compiles them to Lua 5.3 operators, which LuaJIT and Lua 5.2 don't have. |
| `[==[long]==]` | `[[long]]`, or a quoted string when the text contains `]]`. |

### New

- **`++` and `--`:** `x++` and `t.count--` add or subtract 1. They're statements, so
  `y = x++` is an error.
- **`local a = value`:** declares and assigns. MoonScript's `local` only declares, and
  `local a = 1` doesn't parse.
- **Destructured parameters:** a parameter can be a pattern that takes its argument
  apart, as in `area = ({:width, :height}) -> width * height` (see
  [Destructured parameters](REFERENCE.md#destructured-parameters)). MoonScript 0.5.0 has no such
  parameters. It reads `({:width, :height})` as a table in parentheses, called with the
  function `-> width * height`, so the line fails when it runs instead of defining a
  function:

  ```lua
  local area = ({width = width, height = height})(function()
    return width * height
  end)
  ```
- **Properties:** `get name: => @x` and `set name: (v) => ...` in a class body (see
  [Properties](REFERENCE.md#properties)).
- **Metamethods:** `meta {__tostring: => @x}` in a class body (see
  [Metamethods](REFERENCE.md#metamethods)).
- **Numbers:** all of LuaJIT's forms, where MoonScript 0.5.0 lacks `0XFF`, `1e+2`,
  hex floats such as `0x1p4`, and imaginary numbers such as `2i`.
- **Hints:** errors for MoonScript habits like `\`, `!`, `f (x)`, braceless tables,
  `using` and stubs say what to write instead.
