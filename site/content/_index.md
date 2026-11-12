+++
# The home page: index.html lays it out from what's below. Texts are Markdown.
title = "Howlscript"
description = "Howlscript is a clean, explicit language that compiles to Lua, for LuaJIT 2.1 and Lua 5.2 to 5.5."

[extra]
page_title = "Howlscript: a clean, explicit language that compiles to Lua"
tagline = "A clean, explicit language that compiles to Lua."
lede = "Write indentation-based code with classes, comprehensions and string interpolation, and run it on LuaJIT 2.1 and Lua 5.2 to 5.5."
example_name = "pack.howl"
example = '''
```howl
class Pack
  new: (name) =>
    @name = name
    @wolves = {}

  add: (name, age = 1) =>
    @wolves[#@wolves + 1] = {:name, :age}

  get elders: => [w.name for w in *@wolves if w.age > 5]

  meta {
    __tostring: => "#{@name}, #{#@wolves} wolves"
  }

pack = with Pack('Moonrise')
  :add('Akela', 9)
  :add('Grey Brother', 3)

print(pack)                             -- Moonrise, 2 wolves
print(table.concat(pack.elders, ', '))  -- Akela
```
'''

[extra.why]
eyebrow = "Why Howlscript"
title = "Less to write, nothing to guess"
text = "Howlscript keeps Lua's simplicity and speed, and adds the conveniences you miss, without the shortcuts that make code ambiguous."

[[extra.why.features]]
title = "Concise where it counts"
text = "Implicit returns, comprehensions, destructuring, default arguments, string interpolation and `with` blocks."

[[extra.why.features]]
title = "Explicit by design"
text = "Methods take `:`, calls take parentheses and tables take braces, so code reads one way. Compile errors say what's wrong and how to fix it."

[[extra.why.features]]
title = "Classes that do more"
text = "Inheritance and `super`, properties with getters and setters, and metamethods that subclasses inherit."

[[extra.why.features]]
title = "Plain Lua out"
text = "Lua's values, operators and libraries, compiled to plain Lua with nothing to ship alongside it. Lua and Howlscript modules use each other freely."

[[extra.why.features]]
title = "Every modern Lua"
text = "LuaJIT 2.1 and Lua 5.2 to 5.5. The compiler adapts to the Lua it runs on, or compiles for one you name, or for all of them at once."

[[extra.why.features]]
title = "Errors point at your code"
text = "Each statement of the Lua stays on its source line, so runtime errors and tracebacks give the right `.howl` line, without source maps."

[extra.start]
eyebrow = "Get started"
title = "Up and running in a minute"
text = "All you need is a Lua, LuaJIT 2.1 or Lua 5.2 to 5.5, and LuaRocks."

[[extra.start.steps]]
title = "Install"
text = "Howlscript isn't on luarocks.org yet, so point LuaRocks at its rockspec."
code = '''
```sh
luarocks install https://raw.githubusercontent.com/nilnor/howlscript/main/howlscript-scm-1.rockspec
```
'''

[[extra.start.steps]]
title = "Write"
text = "Save this as `hello.howl`."
code = '''
```howl
greet = (name = 'world') -> "Hello, #{name}!"

print(greet())
print(greet('Howlscript'))
```
'''

[[extra.start.steps]]
title = "Run"
text = "Run it, or compile it to a Lua file beside it."
code = '''
```sh
$ howlscript run hello.howl
Hello, world!
Hello, Howlscript!
$ howlscript compile hello.howl   # writes hello.lua
```
'''

[extra.lua]
eyebrow = "Lua in, Lua out"
title = "Fits right into a Lua project"
text = "Load Howlscript as your program runs, or compile it ahead of time and ship plain Lua."

[[extra.lua.cards]]
title = "Require it from Lua"
text = "One call lets `require` find `.howl` modules, compiling them as they load."
code = '''
```lua
require('howlscript').insert_loader()
local notes = require('notes')  -- finds notes.howl
```
'''

[[extra.lua.cards]]
title = "Or compile it ahead of time"
text = "The Lua runs without Howlscript, each statement on its source line."
code = '''
```sh
$ howlscript compile -e 'square = (x) -> x * x'
local square; square = function(x) return x * x end
```
'''

[extra.moonscript]
title = "Coming from MoonScript?"
text = "Howlscript will feel familiar. `howlscript-moon-convert` converts MoonScript 0.5.0 code, keeping its comments and layout, and the guide covers every difference between the two."
+++
