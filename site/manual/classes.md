+++
title = "Classes"
description = "Classes, inheritance, properties and metamethods."
weight = 60
+++

Lua has no classes, only what it takes to build them: a table of methods, a
metatable whose `__index` points at it, and a constructor calling `setmetatable`.
Each Lua library writes that by hand, a little differently. Howlscript's `class`
writes it for you, and adds inheritance, properties and metamethods. The result is
plain tables, which Lua code can use as they are. Each example's Lua tab shows what a
class compiles to.

## Defining a class

```howl
class Wolf
  new: (name, pack) =>
    @name = name
    @pack = pack

  greet: =>
    "#{@name} of the #{@pack} pack"

akela = Wolf('Akela', 'Seeonee')
print(akela:greet())    -- Akela of the Seeonee pack
```

- **The class:** `class Wolf` declares the local `Wolf`, and the lines indented under
  it are its body, which gives its members.
- **Instances:** calling the class creates an instance, passing the arguments on to
  `new`, the constructor. A class without a `new` uses its parent's, if it has one
  ([below](#inheritance)).
- **Methods:** members defined with `=>`, which take `self`
  ([as in the Functions chapter](@/manual/functions.md#methods)). They're called with
  `:`, and in one, `@name` is `self.name` and `@greet()` calls `self:greet()`. A
  function kept in a field, such as a callback, is called without `self` by writing
  the field out: `self.on_done(result)`.
- **A statement:** a class can't be used as a value, so `X = class Wolf` is an
  error. Its name is a plain name, not a field: to put a class in a table, assign it
  there after declaring it.

A class ending a file or function is returned, as an expression would be. So a module
can be a file that ends in its class, `wolf.howl`, and `Wolf = require('wolf')` gets
the class.

## Members

A member that isn't a method, such as a number or a table, is kept in the class too,
shared by all the instances. Each instance reads it there until it sets a field of
its own by that name. That suits constants and defaults, but a table member is one
table for all of them:

```howl
class Pack
  size: 0               -- a default, until a pack sets its own
  members: {}           -- one table, shared by every pack

  add: (name) =>
    @members[#@members + 1] = name
    @size += 1

seeonee = Pack()
waingunga = Pack()
seeonee:add('Akela')
print(seeonee.size, waingunga.size)     -- 1  0
print(#waingunga.members)               -- 1, as both packs share the table
```

`@size += 1` reads the shared `0` and sets the pack's own `size`, so the other pack
keeps the default. `@members` is never set, so both packs add to the class's table.
To give each instance a table of its own, create it in `new`, as in
`@members = {}`.

Members are keyed as in a table: `name: value`, `'text': value` for a key that isn't
a name, and `[expr]: value` for any other key.

## The class body

A class body runs from top to bottom when the class is defined, and can hold
statements as well as members:

- **Locals:** a name assigned in the body is a local of the body, which the methods
  can use but code outside the class can't. That makes it the place for private
  helpers and constants. As anywhere, assigning a name that's already a local
  outside the class updates that local instead, so a helper sharing its name takes
  `local`.
- **Order:** a member can use the locals assigned above it. Methods can use those
  assigned anywhere in the body, as they run later, but reading a local in the body
  before it's assigned is an error, as it's still `nil` there.
- **`:name`** is short for `name: name`, a member taking the value of the local of
  that name.
- **`self`:** statements in the body run with `self` being the class, which they
  can't assign. The class also has its name from the `class` line on, so the body
  can use that too.

```howl
class Den
  capacity = 6                -- a local of the class body

  clamp = (n) ->
    math.min(n, capacity)

  new: (wolves) =>
    @wolves = clamp(wolves)

  :capacity                   -- the member capacity: capacity

print(Den(9).wolves)          -- 6
print(Den.capacity)           -- 6, read from the class
print(clamp)                  -- nil, as the local is the class body's
```

## Class variables and methods

`@name: value` in the body puts a value on the class itself rather than in its
instances: a class variable, or with `=>`, a class method, whose `self` is the
class. In an instance's method, `@@` is the instance's class, so `@@name` is a class
variable and `@@name()` calls a class method:

```howl
class Wolf
  @count: 0

  @from_names: (names) =>
    [@(name) for name in *names]    -- @ is the class here, so this creates wolves

  new: (name) =>
    @name = name
    @@count += 1

pack = Wolf:from_names({'Akela', 'Raksha', 'Grey'})
print(#pack, pack[2].name)      -- 3  Raksha
print(Wolf.count)               -- 3
```

A subclass reads its parent's class variables through `@@`, but assigning one
through it sets the subclass's own, which takes over from then on. So in the
instances of a subclass of `Wolf`, `@@count += 1` would give the subclass a count
of its own, going on from `Wolf`'s. To keep one count, name the class, as in
`Wolf.count += 1`.

## Inheritance

`extends` makes a class a subclass of another, which it takes its members from.
`super` reaches the parent's version of what the subclass replaces:

```howl
class Animal
  new: (name) =>
    @name = name

  speak: =>
    "#{@name} makes a sound"

class Wolf extends Animal
  new: (name, pack) =>
    super(name)
    @pack = pack

  speak: =>
    super() .. ', a long howl'

grey = Wolf('Grey', 'Seeonee')
print(grey:speak())     -- Grey makes a sound, a long howl
print(grey.pack)        -- Seeonee
```

- **The parent** can be any expression, as in `class Cub extends require('wolf')`.
- **`new`:** a subclass without a `new` uses its parent's.
- **`super(...)`** calls the parent's version of the method it's in: in `new` the
  parent's constructor, and in a class method `@name:` the parent's `name`. It's
  called on the same `self`.
- **`super:m(...)`** calls any of the parent's methods on `self`, as in
  `super:speak()` from another method.
- **`super.x`** reads `x` from the parent class, and `super` alone is the parent
  class.
- **Where:** `super` works in the methods of a class with a parent, including the
  functions inside them. In a class without one it's an error,
  `'super' needs a parent class, given with 'extends'`.

A class is told when it's extended: its class method `__inherited`, if it has one,
is called with the subclass. That's a way to keep track of the subclasses:

```howl
class Plugin
  @registry: {}

  @__inherited: (child) =>
    @registry[#@registry + 1] = child.__name

class Spellcheck extends Plugin
class Linter extends Plugin

print(table.concat(Plugin.registry, ', '))     -- Spellcheck, Linter
```

## Properties

Lua code exposes a computed value through a method, as in `den:size()`, or with an
`__index` function in the metatable. A property reads like a field and is computed
by a method, its getter. `get name: value` gives the property `name` a getter, and
`set name: value` a setter, which is called when the property is assigned:

```howl
class Den
  new: (wolves) =>
    @wolves = wolves

  get size: =>
    #@wolves

  get leader: =>
    @wolves[1]

  set leader: (name) =>
    table.insert(@wolves, 1, name)

den = Den({'Raksha', 'Grey'})
den.leader = 'Akela'          -- through the setter
print(den.leader, den.size)   -- Akela  3
```

- **Accessors:** the getter takes no parameters, and the setter takes the value.
  They're separate items of the class, in either order, and normally go together,
  the getter first.
- **Read-only:** a property with only a getter is read-only, and assigning to it is
  an error when it runs, `property 'size' is read-only`. One with only a setter is
  write-only, and reading it is an error too.
- **Everywhere:** a property is used through its accessors also inside the class, so
  `@leader = name` in `new` would call the setter.
- **One kind of name:** a property wins over a member of the same name in a parent
  class. Within one class, a name can't be both a property and a member.

A subclass inherits its parent's properties. An accessor it gives replaces the
parent's of the same kind and keeps the other, and in it, `super()` calls the
parent's getter and `super(value)` its setter:

```howl
class LoudDen extends Den
  get leader: =>
    super():upper()           -- Den's getter; Den's setter is kept

den = LoudDen({'Grey'})
den.leader = 'Raksha'
print(den.leader)             -- RAKSHA
```

`get` and `set` mean this only at the start of a class item, followed by a name and a
colon, so methods named `get` and `set` still work.

## Metamethods

In Lua, a value's operators and `tostring` come from metamethods in its metatable.
A class gives its instances metamethods with `meta`, a table keyed by their Lua
names:

```howl
class Version
  new: (major, minor) =>
    @major = major
    @minor = minor

  meta {
    __eq: (other) =>
      @major == other.major and @minor == other.minor

    __lt: (other) =>
      return @minor < other.minor if @major == other.major
      @major < other.major

    __tostring: =>
      "#{@major}.#{@minor}"
  }

versions = {Version(2, 1), Version(1, 9), Version(2, 0)}
table.sort(versions)
print(versions[1], versions[3])         -- 1.9  2.1
print(Version(2, 0) == Version(2, 0))   -- true
```

- **Inherited:** subclasses inherit the metamethods, and a subclass's own `meta`
  replaces those it gives. In a metamethod, `super(...)` calls the parent's.
- **Every Lua's:** `meta` takes the metamethods of all the Luas Howlscript compiles
  for, such as Lua 5.4's `__close`, and a Lua ignores those it doesn't have.
- **Only there:** a member named after a metamethod is an error, which says to use
  `meta`. So is a name that isn't one of Lua's metamethods, or a second `meta` in a
  class.

### Fallbacks

`__index` and `__newindex` in `meta` are fallbacks, called for the keys a class
doesn't handle itself. `__index` is called with a key that the instance doesn't have
as a field, property or method, and `__newindex` with a key and a value for an
assignment to a key that isn't a field or property. That makes them the way to pass
keys on to another table:

```howl
class Tracked
  new: (values) =>
    rawset(self, 'values', values)    -- not through __newindex
    rawset(self, 'changed', {})

  get count: =>
    #@changed

  meta {
    __index: (key) =>
      @values[key]

    __newindex: (key, value) =>
      @changed[#@changed + 1] = key
      @values[key] = value
  }

settings = Tracked({width: 80})
settings.width = 100
print(settings.width, settings.count)   -- 100  1
```

With a `__newindex`, setting a new field in `new` goes through it too, so `new` sets
its fields with `rawset`. Either fallback can also be a table, which the key is then
read from or set in.

## Class membership

`is_a` asks whether a value is an instance of a class or of one of its subclasses.
A class itself counts too, so `Wolf is_a Animal` is true. It's false for a value
that isn't one — an instance of another class, or a number, string or nil. It isn't
a reserved word: it only acts as an operator between two expressions, so `is_a(x)`
still calls a function of that name.

```howl
class Animal
class Wolf extends Animal

print(Wolf() is_a Animal)     -- true
print(Wolf() is_a Wolf)       -- true
print(Animal() is_a Wolf)     -- false
print(Wolf is_a Animal)       -- true, for the class itself
print(Wolf() is_a 'table')    -- true, as an instance is a table
print(7 is_a 'number')        -- true
print(7 is_a 'string')        -- false
print(not (7 is_a 'string'))  -- true
```

To negate the test, put it in parentheses: `not` binds tighter than `is_a`, as it
does than `==`, so `not x is_a Wolf` would test `not x`, and is an error.

A string on the right names a Lua type instead, compared with `type(x)`, so it's a
test of any value ([Types](@/manual/tour.md#types) has the names): `Wolf() is_a
'table'` is true, as a class and its instances are tables like any other. That's
also why a class is always given as a value: `x is_a 'Wolf'` would ask whether `x`
has the Lua type `Wolf`, which nothing does, so it's an error. A class name that
isn't defined, as when it's misspelt or its module isn't required, is `nil`, and
`is_a` raises an error when it gets that.

## From Lua

A class is a table, which Lua code uses as one: calling it creates an instance,
and an instance is a plain table holding what its methods set. So `Wolf('Akela')`
in a Lua file is the same call as in Howlscript, `wolf.name` reads the field a
method set, and `wolf:greet()` calls the method.

A class's tables have a few fields of their own, described in the reference's
[Layout](@/reference.md#layout-1) section. That layout isn't settled yet, so Lua
code shouldn't depend on it.

A class with a parent, properties or metamethods also needs some support code,
which the compiler adds once at the start of the file. The Lua tabs in this chapter
leave its body out, saying how many lines that is.

## Where next

The [reference](@/reference.md#classes) has the exact rules for classes,
[`@` and `@@`](@/reference.md#and), [properties](@/reference.md#properties) and
[metamethods](@/reference.md#metamethods).
