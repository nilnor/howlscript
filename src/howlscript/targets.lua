-- Copyright 2026 Nils Nordman
-- License: MIT (see LICENSE.md at the top-level directory of the distribution)

-- The Luas the compiler can compile for, by name, each with what it supports of
-- what runtime.lua finds in the running Lua. `portable` is Lua that loads on all of
-- them.

return {
  luajit = { u_escapes = true, assignable_loop_vars = true, ffi_numbers = true },
  ['5.2'] = { u_escapes = false, assignable_loop_vars = true, ffi_numbers = false },
  ['5.3'] = { u_escapes = true, assignable_loop_vars = true, ffi_numbers = false },
  ['5.4'] = { u_escapes = true, assignable_loop_vars = true, ffi_numbers = false },
  ['5.5'] = { u_escapes = true, assignable_loop_vars = false, ffi_numbers = false },
  portable = { u_escapes = false, assignable_loop_vars = false, ffi_numbers = false },
}
