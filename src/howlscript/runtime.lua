-- Copyright 2026 Nils Nordman
-- License: MIT (see LICENSE.md at the top-level directory of the distribution)

-- What the running Lua supports where LuaJIT and Lua 5.2 to 5.5 differ in ways the
-- compiled Lua depends on. Each is found by loading a snippet, so the compiler
-- adapts to the Lua it runs on rather than to a version number.

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
}
