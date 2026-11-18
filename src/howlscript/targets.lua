-- Copyright 2026 Nils Nordman
-- License: MIT (see LICENSE.md at the top-level directory of the distribution)

-- The Luas the compiler can compile for, by name, each with what it supports of
-- what runtime.lua finds in the running Lua. `luajit` is any LuaJIT 2.1, and
-- `luajit-2026` one built since July 2026, which has the bitwise operators.
-- `portable` is Lua that loads on all of them, which has no bitwise operators
-- (`bitwise` false).

return {
  luajit = {
    u_escapes = true, assignable_loop_vars = true, ffi_numbers = true,
    bitwise = 'bit', floor_division = false,
  },
  ['luajit-2026'] = {
    u_escapes = true, assignable_loop_vars = true, ffi_numbers = true,
    bitwise = 'operators', floor_division = false,
  },
  ['5.2'] = {
    u_escapes = false, assignable_loop_vars = true, ffi_numbers = false,
    bitwise = 'bit32', floor_division = false,
  },
  ['5.3'] = {
    u_escapes = true, assignable_loop_vars = true, ffi_numbers = false,
    bitwise = 'operators', floor_division = true,
  },
  ['5.4'] = {
    u_escapes = true, assignable_loop_vars = true, ffi_numbers = false,
    bitwise = 'operators', floor_division = true,
  },
  ['5.5'] = {
    u_escapes = true, assignable_loop_vars = false, ffi_numbers = false,
    bitwise = 'operators', floor_division = true,
  },
  portable = {
    u_escapes = false, assignable_loop_vars = false, ffi_numbers = false,
    bitwise = false, floor_division = false,
  },
}
