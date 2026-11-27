-- Copyright 2026 Nils Nordman
-- License: MIT (see LICENSE.md at the top-level directory of the distribution)

-- Lexical scopes, as the compiler walks the AST. A scope holds the locals declared
-- in it, by name in `names` and in the order of their declarations in `order`, and
-- the compiler adds `fn`, the function it's in, and `labels`, the labels of its
-- block.

if jit then jit.off(true, true) end -- see the note in compiler.lua

local Scope = {}
Scope.__index = Scope

local function new(parent)
  return setmetatable({
    parent = parent,
    names = {},
    order = {},
  }, Scope)
end

function Scope:declare(name, line)
  local decl = { line = line, name = name }
  self.names[name] = decl
  self.order[#self.order + 1] = decl
  return decl
end

-- The declaration of the local `name` visible from this scope, if any.
function Scope:lookup(name)
  local scope = self
  while scope do
    local decl = scope.names[name]
    if decl then return decl end
    scope = scope.parent
  end
end

-- Whether an assignment to `name` declares a new local: whenever no local of that
-- name is visible, as globals are only assigned through _G.
function Scope:is_fresh(name)
  return not self:lookup(name)
end

return {
  new = new,
}
