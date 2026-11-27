-- Copyright 2026 Nils Nordman
-- License: MIT (see LICENSE.md at the top-level directory of the distribution)

-- What the running Lua supports where LuaJIT and Lua 5.2 to 5.5 differ in ways the
-- compiled Lua depends on. Each is found by loading a snippet, so the compiler
-- adapts to the Lua it runs on rather than to a version number. The compiler
-- compiles for this Lua unless given one of targets.lua.

local function loads(code)
  return load(code, '=probe', 't') ~= nil
end

return {
  -- `\u{XXX}` escapes in strings, which Lua 5.2 lacks
  u_escapes = loads('return "\\u{41}"'),

  -- assigning to the variables of a for loop, which Lua 5.5 makes constants
  assignable_loop_vars = loads('for i = 1, 1 do i = 2 end'),

  -- the numbers of LuaJIT's FFI: 64-bit integers (`1LL`, `1ULL`) and imaginary
  -- numbers (`1i`)
  ffi_numbers = loads('return 1LL'),

  -- how the bitwise operators compile: to the operators of Lua 5.3+ and of LuaJIT
  -- 2.1 since July 2026, or else to the functions of LuaJIT's `bit` library or Lua
  -- 5.2's `bit32`
  bitwise = loads('return 1 & 1') and 'operators' or loads('return 1LL') and 'bit' or 'bit32',

  -- `//`, which Lua 5.3+ has, and which otherwise compiles to math.floor(a / b)
  floor_division = loads('return 1 // 1'),

  -- to-be-closed locals, `local x <close> = v`, which Lua 5.4+ has
  close = loads('local x <close> = nil'),
}
