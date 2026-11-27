-- Copyright 2026 Nils Nordman
-- License: MIT (see LICENSE.md at the top-level directory of the distribution)

-- Compiles the AST from the parser into Lua, in a single pass that also resolves
-- names: an assignment to a name that isn't visible declares a new local.
--
-- The blocks that are values, with and comprehensions, are lowered with a "sink"
-- saying what to do with their value: return it, assign it, or discard it. When
-- such a block is assigned or returned it's lowered in place; anywhere else in an
-- expression it becomes an immediately called function (an IIFE). The other blocks
-- (if, switch, do and loops) are statements, without a value, also as the last
-- statement of a function. Statement modifiers (`f(x) if x`) are separate from the
-- if statement: they pass on the value of the statement they modify.
--
-- Generated names start with `__hs`, which the lexer doesn't allow in source.

-- The JIT only slows code this recursive and branchy down: it keeps recording
-- traces that abort, which made compiling several times slower.
if jit then jit.off(true, true) end

local Scope = require('howlscript.scope')
local Emitter = require('howlscript.emitter')
local raise = require('howlscript.errors').raise
local runtime = require('howlscript.runtime')

local concat = table.concat
-- string functions are used directly rather than as methods, since a program
-- using the compiler can give strings an __index function, making method calls slow
local format, match, lower, find = string.format, string.match, string.lower, string.find

local lua_keywords = {}
for kw in ([[
  and break do else elseif end false for function goto if in local nil not or
  repeat return then true until while
]]):gmatch('%a+') do
  lua_keywords[kw] = true
end

-- Lua keywords that Howlscript doesn't reserve, so they can reach the compiler as names
local lua_only = { ['end'] = true, ['function'] = true, ['goto'] = true, ['repeat'] = true, ['until'] = true }

local function valid_name(s)
  return not lua_keywords[s] and match(s, '^[%a_][%w_]*$') ~= nil
end

local function field(name)
  if valid_name(name) then return '.' .. name end
  return '[' .. format('%q', name) .. ']'
end

local function key(name)
  if valid_name(name) then return name end
  return '[' .. format('%q', name) .. ']'
end

-- Lua operator precedences, for parenthesizing
local precedence = {
  ['or'] = 1, ['and'] = 2,
  ['<'] = 3, ['>'] = 3, ['<='] = 3, ['>='] = 3, ['=='] = 3, ['~='] = 3, ['!='] = 3,
  ['|'] = 4, ['~'] = 5, ['&'] = 6, ['<<'] = 7, ['>>'] = 7,
  ['..'] = 8, ['+'] = 9, ['-'] = 9, ['*'] = 10, ['/'] = 10, ['//'] = 10, ['%'] = 10,
  ['^'] = 12,
}
local UNARY = 11

-- The functions of LuaJIT's `bit` and Lua 5.2's `bit32` that the bitwise operators
-- compile to on a Lua without them. band, bor and bxor take any number of values.
local bit_functions = {
  ['&'] = 'band', ['|'] = 'bor', ['~'] = 'bxor', ['<<'] = 'lshift', ['>>'] = 'rshift',
}
local nary_bit_ops = { ['&'] = true, ['|'] = true, ['~'] = true }

local value_blocks = { With = true, Comprehension = true }
-- the literals that `and` and `or` can test
local literals = { Nil = true, True = true, False = true, Number = true, String = true }
-- the expressions that can give several values
local multi_valued = { Call = true, MethodCall = true, WithCall = true, Vararg = true }
local calls = { Call = true, MethodCall = true, WithCall = true }

-- what Lua accepts as the receiver of a call, index or field access without
-- parentheses (immediately called functions included)
local prefix_kinds = {
  Name = true, Field = true, Index = true, Call = true, MethodCall = true,
  WithCall = true, Paren = true, Self = true, SelfField = true, ClassRef = true,
  ClassField = true, WithField = true, Raw = true, Super = true,
}
for k in pairs(value_blocks) do prefix_kinds[k] = true end

local function raw(code)
  return { k = 'Raw', code = code }
end

-- Expressions that are cheap and without side effects, so they can be evaluated
-- more than once.
local function is_simple(e)
  local k = e.k
  if k == 'Name' or k == 'Self' or k == 'SelfField' or k == 'Number' or k == 'Raw'
    or k == 'Nil' or k == 'True' or k == 'False' then
    return true
  end
  if k == 'String' then
    for _, p in ipairs(e.parts) do
      if type(p) ~= 'string' then return false end
    end
    return true
  end
  return false
end

-- Expressions that are plain lookups, repeated for each name a pattern extracts.
local function is_path(e)
  local k = e.k
  if k == 'Name' or k == 'Self' or k == 'SelfField' or k == 'Raw' then return true end
  return k == 'Field' and is_path(e.obj)
end

-- Whether a loop body has a `continue` for the loop itself.
local stops_continue = { For = true, ForIn = true, While = true, Func = true, Comprehension = true }
local function has_continue(n)
  if n.k == 'Continue' then return true end
  if n.k and stops_continue[n.k] then return false end
  for _, v in pairs(n) do
    if type(v) == 'table' and has_continue(v) then return true end
  end
  return false
end

local function target_names(t, names)
  if t.k == 'Name' then
    names[t.v] = true
  elseif t.k == 'Pattern' then
    for _, entry in ipairs(t.entries) do
      if entry.target then target_names(entry.target, names) end
    end
  end
end

-- The names assigned anywhere inside a node, nested functions included, as a set.
local function assigned_names(n, names)
  names = names or {}
  if n.k == 'Assign' then
    for _, t in ipairs(n.targets) do target_names(t, names) end
  elseif n.k == 'Update' then
    target_names(n.target, names)
  end
  for _, v in pairs(n) do
    if type(v) == 'table' then assigned_names(v, names) end
  end
  return names
end

-- The names assigned inside a loop or comprehension, where the target makes loop
-- variables constants (Lua 5.5), and nil elsewhere. A loop variable among them is
-- then a local copy of a hidden one.
local function assigned_loop_vars(n, target)
  if target.assignable_loop_vars then return nil end
  return assigned_names(n)
end

local DISCARD = { k = 'discard' }
local IMPLICIT_RETURN = { k = 'return' }

-- Lua's metamethods, which a class passes on to its subclasses: Lua looks them up
-- in the metatable itself, so the base of a subclass needs copies of them. They're
-- those of every Lua version, whichever runs the compiler, so that a class can
-- give each Lua its own: a Lua ignores the ones it doesn't know.
local metamethods = {
  '__tostring', '__len', '__eq', '__lt', '__le', '__concat', '__call', '__unm', '__add',
  '__sub', '__mul', '__div', '__mod', '__pow', '__pairs', '__ipairs', '__mode', '__gc',
  '__idiv', '__band', '__bor', '__bxor', '__shl', '__shr', '__bnot', '__close',
  '__metatable',
}
local is_metamethod = {}
for _, name in ipairs(metamethods) do is_metamethod[name] = true end
-- What else goes in a class's meta: __name, which each class has of its own, its
-- name by default, so it isn't passed on.
local is_meta_field = { __name = true }

-- The runtime support for classes, prepended on the first line of files that need
-- it, so the Lua stays self-contained.
--
-- `__hs_setup(class, own)` runs when a class is created. It copies the metamethods
-- of the ancestors' bases, and the `__index:` and `__newindex:` fallbacks
-- (`__hs_index`, `__hs_newindex`). A class with properties or fallbacks of its own
-- (`own`), or with an ancestor that dispatches, then dispatches too: its base gets
-- `__properties`, a flat table of `{get, set}` by name that starts out with the
-- ancestors' properties, and `__index` and `__newindex` functions that go through
-- the properties, the methods, the fallbacks and finally the instance. Methods are
-- looked up raw along the chain of bases, so that the dispatcher of a parent never
-- runs with the base of a subclass as `self`. It returns the properties table.
--
-- A base's parent base is found through its `__class` and that class's `__parent`,
-- not with getmetatable, which a `__metatable` in the parent's base would answer.
local CLASS_SUPPORT = string.gsub([[
local __hs_setup
do
  local rawget, rawset, pairs, type, error, tostring =
    rawget, rawset, pairs, type, error, tostring
  local inherited_keys = {'__hs_index', '__hs_newindex', ]] ..
  "'" .. table.concat(metamethods, "', '") .. "'" .. [[}
  local function parent_base(a)
    local p = rawget(rawget(a, '__class'), '__parent')
    return p and rawget(p, '__base')
  end
  local function dispatch(b, props)
    rawset(b, '__properties', props)
    local chain, n, a = {}, 0, b
    while a do
      n = n + 1
      chain[n] = a
      a = parent_base(a)
    end
    rawset(b, '__index', function(o, k)
      local p = props[k]
      if p ~= nil then
        local get = p.get
        if get == nil then error("property '" .. tostring(k) .. "' is write-only", 2) end
        return get(o)
      end
      for i = 1, n do
        local v = rawget(chain[i], k)
        if v ~= nil then return v end
      end
      local f = rawget(b, '__hs_index')
      if type(f) == 'function' then return f(o, k) end
      if f ~= nil then return f[k] end
    end)
    rawset(b, '__newindex', function(o, k, v)
      local p = props[k]
      if p ~= nil then
        local set = p.set
        if set == nil then error("property '" .. tostring(k) .. "' is read-only", 2) end
        set(o, v)
        return
      end
      local f = rawget(b, '__hs_newindex')
      if type(f) == 'function' then
        f(o, k, v)
      elseif f ~= nil then
        f[k] = v
      else
        rawset(o, k, v)
      end
    end)
  end
  __hs_setup = function(c, own)
    local b, parent, props = rawget(c, '__base'), rawget(c, '__parent'), nil
    local a = parent and rawget(parent, '__base')
    while a do
      for i = 1, #inherited_keys do
        local k = inherited_keys[i]
        if rawget(b, k) == nil then rawset(b, k, rawget(a, k)) end
      end
      local inherited = rawget(a, '__properties')
      if inherited then
        props = props or {}
        for k, p in pairs(inherited) do
          if props[k] == nil then props[k] = p end
        end
      end
      a = parent_base(a)
    end
    if own or props then
      props = props or {}
      dispatch(b, props)
    end
    return props
  end
end
]], '\n%s*', ' ')

local Compiler = {}
Compiler.__index = Compiler

-- the stmt_<Kind> and e_<Kind> methods by node kind, filled in at the end
local stmt_handlers, expr_handlers = {}, {}

local function new(source, target)
  return setmetatable({
    E = Emitter.new(source),
    target = target, -- what the Lua compiled for supports (see targets.lua)
    n_tmp = 0,
    with_stack = {},
    cls = nil,     -- the class being compiled: { c, b, p, method, static, accessor }
    fn = nil,      -- the function being compiled: { vararg, iife, loop }, and an
                   -- iife's `parent`, the function it runs in
    scope = nil,
    needs_invoke = false,
    needs_class_support = false,
    bit_helpers = {}, -- the bit library functions used, by name
    needs_floor = false,
    needs_is_a = false,
    globals = {}, -- the Lua globals the compiled code uses, by name (see global())
  }, Compiler)
end

function Compiler:error(message, n, len)
  raise(message, n.line or 1, n.col or 1, len)
end

-- The name for a Lua global that compiled code uses, such as tostring: a local taken
-- on line 1, before the source's own code, which could declare a local of the
-- global's name.
function Compiler:global(name)
  self.globals[name] = true
  return '__hs_' .. name
end

function Compiler:tmp(what)
  self.n_tmp = self.n_tmp + 1
  return '__hs_' .. what .. self.n_tmp
end

function Compiler:push_scope()
  self.scope = Scope.new(self.scope)
  self.scope.fn = self.fn
end

function Compiler:pop_scope()
  self.scope = self.scope.parent
end

function Compiler:check_name(name, n)
  if lua_only[name] then
    self:error(format("'%s' is a Lua keyword and can't be used as a variable name", name), n, #name)
  end
end

function Compiler:declare_all(names, line)
  for _, name in ipairs(names) do
    self.scope:declare(name, line)
  end
end

-- Declares a parameter or loop variable, which may not shadow a visible local,
-- other than one being assigned the value it's in.
function Compiler:bind(name, n, what)
  self:check_name(name, n)
  if name ~= '_' and name ~= 'self' then
    local decl = self.scope:lookup(name)
    if decl and not decl.assigning then
      self:error(format(
        "%s '%s' shadows the local declared on line %d; rename one of them",
        what, name, decl.line), n, #name)
    end
  end
  self.scope:declare(name, n.line)
end

function Compiler:need_self(n)
  if not self.scope:lookup('self') then
    self:error("'@' refers to self, but there's none here; methods are defined with '=>'", n)
  end
end

function Compiler:with_var(n)
  local var = self.with_stack[#self.with_stack]
  if not var then
    self:error('this refers to the target of a with block, but there is none here', n)
  end
  return var
end

function Compiler:super_cls(n, need_method)
  local cls = self.cls
  if not cls or (need_method and not cls.method) then
    self:error("'super' can only be used in a class method", n)
  end
  if not cls.p then
    self:error("'super' needs a parent class, given with 'extends'", n)
  end
  return cls
end

-- Blocks and sinks

function Compiler:stmt(s)
  local handler = stmt_handlers[s.k]
  if not handler then
    self:error('unexpected ' .. s.k, s)
  end
  handler(self, s)
end

-- Compiles a list of statements. The last one's value goes to `sink`, and with
-- `wrap_last` a final return or break is wrapped in do ... end, since Lua code
-- follows it. `code_follows` says that code other than a label follows the
-- statements in their Lua block.
function Compiler:block(stmts, sink, wrap_last, code_follows)
  if sink == DISCARD then sink = nil end
  local n = #stmts
  self:declare_labels(stmts, code_follows)
  for i = 1, n do
    local s = stmts[i]
    local jump = s.k == 'Return' or s.k == 'Break' or s.k == 'Continue' or s.k == 'Goto'
    -- a label after a jump is reachable through a goto
    if i < n and jump and stmts[i + 1].k ~= 'Label' then
      self:error("unreachable code after '" .. lower(s.k) .. "'", stmts[i + 1])
    end
    if i < n and (s.k == 'Return' or s.k == 'Break') then
      -- Lua code follows it
      stmt_handlers[s.k](self, s, true)
    elseif i < n then
      self:stmt(s)
    elseif sink then
      self:tail(s, sink, wrap_last)
    elseif wrap_last and (s.k == 'Return' or s.k == 'Break') then
      stmt_handlers[s.k](self, s, true)
    else
      self:stmt(s)
    end
  end
end

-- Labels and gotos follow Lua's rules, checked here so that the Lua always loads. A
-- label is visible in its whole block and the blocks inside it, in the same
-- function, and can't be declared where one of its name is visible. A goto jumps
-- to a visible label, but not forward into the scope of a local declared on the
-- way, unless the label ends its block, where the locals' scopes have ended.

-- Declares the labels among the statements of a block, before compiling them, so
-- that gotos see those further on.
function Compiler:declare_labels(stmts, code_follows)
  local labels
  for i, s in ipairs(stmts) do
    if s.k == 'Label' then
      self:check_name(s.name, s.name_tok)
      local seen = labels and labels[s.name] or self:visible_label(s.name)
      if seen then
        self:error(format("the label '%s' is already declared on line %d, and visible here",
          s.name, seen.line), s.name_tok, #s.name)
      end
      -- only labels may follow one ending the block
      local last = not code_follows
      for j = i + 1, #stmts do
        if stmts[j].k ~= 'Label' then last = false end
      end
      labels = labels or {}
      labels[s.name] = { line = s.line, last = last, gotos = {} }
    end
  end
  self.scope.labels = labels
end

-- The label `name` visible here, and the scope of its block.
function Compiler:visible_label(name)
  local scope = self.scope
  while scope and scope.fn == self.fn do
    local label = scope.labels and scope.labels[name]
    if label then return label, scope end
    scope = scope.parent
  end
end

function Compiler:stmt_Goto(s)
  local label, scope = self:visible_label(s.label)
  if not label and self.fn.iife then
    self:error("'goto' can't be used here, as the expression it's in is compiled to a function; use a statement instead", s, 4)
  elseif not label then
    self:error(format("no label '%s' is visible from here; a goto jumps to a label in its block or one around it, in the same function",
      s.label), s.label_tok, #s.label)
  end
  if not label.reached then
    -- a forward jump, checked at the label against the locals declared by then
    label.gotos[#label.gotos + 1] = { s = s, declared = #scope.order }
  end
  self.E:stmt(s.line)
  self.E:w('goto ' .. s.label)
end

function Compiler:stmt_Label(s)
  local label = self.scope.labels and self.scope.labels[s.name]
  if not label then
    self:error('a label can only be a statement of a block', s)
  end
  label.reached = true
  local order = self.scope.order
  if not label.last then
    for _, g in ipairs(label.gotos) do
      local decl = order[g.declared + 1]
      if decl then
        self:error(format("this goto would jump into the scope of '%s', declared on line %d before the label '%s', which Lua doesn't allow; declare it before the goto with 'local %s', or end the block with the label",
          decl.name, decl.line, s.name, decl.name), g.s, 4)
      end
    end
  end
  self.E:stmt(s.line)
  self.E:w('::' .. s.name .. '::')
end

-- Compiles the last statement of a block, sending its value to the sink.
function Compiler:tail(s, sink, wrap)
  local k = s.k
  if k == 'ExprStmt' then
    if #s.exprs == 1 and value_blocks[s.exprs[1].k] then
      return self:lower(s.exprs[1], sink)
    end
    if sink.k == 'discard' or (sink == IMPLICIT_RETURN and self:calls_error(s.exprs)) then
      return self:stmt_ExprStmt(s)
    end
    if self:hoist(s.line, s.exprs, nil, function(exprs) self:apply(sink, exprs) end) then
      return
    end
    return self:apply(sink, s.exprs, s.line)
  elseif k == 'If' and s.decorator then
    -- a modifier passes on the value of the statement it modifies: -> f(x) if x
    return self:stmt_If(s, sink)
  elseif k == 'If' or k == 'Switch' or k == 'Do' then
    -- statements without a value: a function or file ending in one returns nothing
    return stmt_handlers[k](self, s)
  elseif k == 'With' then
    return self:lower(s, sink)
  elseif k == 'Return' or k == 'Break' then
    return stmt_handlers[k](self, s, wrap)
  elseif sink.k ~= 'discard' and k == 'Class' then
    self:stmt(s)
    return self:apply(sink, { { k = 'Name', v = s.name } })
  end
  self:stmt(s)
end

-- Whether `exprs` is a call of Lua's error, which never returns. Ending a function,
-- it's left a plain call: as `return error(...)`, a tail call, LuaJIT's message
-- would have no position, the calling function's frame being gone.
function Compiler:calls_error(exprs)
  local e = exprs[1]
  return #exprs == 1 and e.k == 'Call' and e.fn.k == 'Name' and e.fn.v == 'error'
    and not self.scope:lookup('error')
end

-- Sends the values of `exprs` to the sink.
function Compiler:apply(sink, exprs, line)
  local E = self.E
  local k = sink.k
  if k == 'discard' then
    return self:stmt_ExprStmt({ k = 'ExprStmt', exprs = exprs, line = line, col = exprs[1].col })
  end
  E:stmt(line)
  if k == 'return' then
    E:w('return ')
    self:expr_list(exprs)
  elseif k == 'assign' then
    self:targets(sink.targets)
    E:w(' = ')
    self:expr_list(exprs)
  end
end

-- Lowers a block used as a value in place, sending its value to the sink.
function Compiler:lower(e, sink)
  local k = e.k
  if k == 'With' then
    return self:lower_with(e, sink)
  elseif k == 'Comprehension' then
    if sink.k == 'discard' then
      self:error('this comprehension does nothing; only calls can be statements', e)
    end
    return self:lower_comprehension(e, sink)
  end
  return self:apply(sink, { e }, e.line)
end

-- If, switch and do take a sink for the last statements of their bodies only from
-- tail(): a modifier's to pass on a value, and otherwise one marking the end of a
-- function, where values have to be returned explicitly.
function Compiler:stmt_If(s, sink)
  local E = self.E
  E:stmt(s.line)

  -- `x = 1 if c` declares x outside the if, where it can be used
  local inner = s.decorator and s.bodies[1][1]
  if inner and inner.k == 'Assign' and inner.attribs then
    self:error("a statement declaring '<const>' or '<close>' names can't have an 'if' or 'unless' after it, as the names would be set only when it holds", inner)
  end
  if inner and inner.k == 'Assign' then
    local fresh, seen = {}, {}
    for _, t in ipairs(inner.targets) do
      if t.k == 'Name' and self.scope:is_fresh(t.v) and not seen[t.v] then
        self:check_name(t.v, t)
        fresh[#fresh + 1] = t.v
        seen[t.v] = true
      end
    end
    if #fresh > 0 then
      E:w('local ' .. concat(fresh, ', ') .. '; ')
      self:declare_all(fresh, s.line)
    end
  end

  for i, cond in ipairs(s.conds) do
    if i == 1 then
      E:w('if ')
    else
      E:sp(cond.line)
      E:w('elseif ')
    end
    if i == 1 and s.unless then
      E:w('not ')
      self:expr(cond, UNARY)
    else
      self:expr(cond)
    end
    E:w(' then')
    self:push_scope()
    self:block(s.bodies[i], sink)
    self:pop_scope()
  end

  if s.else_body then
    E:sp()
    E:w('else')
    self:push_scope()
    self:block(s.else_body, sink)
    self:pop_scope()
  end
  E:sp()
  E:w('end')
end

-- Rejects a `when` value that's an `and` or `or` after a literal, as in
-- `when 'a' or 'b'`: it gives the same side whatever is switched on, so only that
-- one value is compared, where several were likely meant.
function Compiler:check_when_value(v)
  local e = v
  while e.k == 'Binop' and (e.op == 'or' or e.op == 'and') do
    if literals[e.l.k] then
      self:error(format(
        "'%s' after a literal always gives the same side, so this compares a single value; to match several, separate them with commas, as in when 'a', 'b'",
        e.op), e.op_tok, #e.op)
    end
    e = e.l
  end
end

function Compiler:stmt_Switch(s, sink)
  local E = self.E
  E:stmt(s.line)
  local subject = s.subject
  local tmp
  if not is_simple(subject) then
    tmp = self:tmp('switch')
    E:w('do local ' .. tmp .. ' = ')
    self:expr(subject)
    E:w(';')
    subject = raw(tmp)
  end

  for i, clause in ipairs(s.clauses) do
    if i == 1 then
      E:sp()
      E:w('if ')
    else
      E:sp(clause.line)
      E:w('elseif ')
    end
    -- the case value goes on the left, so its __eq is the one used
    local cond
    for _, v in ipairs(clause.values) do
      self:check_when_value(v)
      local test = { k = 'Binop', op = '==', l = v, r = subject, line = v.line }
      cond = cond and { k = 'Binop', op = 'or', l = cond, r = test, line = cond.line } or test
    end
    self:expr(cond)
    E:w(' then')
    self:push_scope()
    self:block(clause.body, sink)
    self:pop_scope()
  end

  if s.else_body then
    E:sp()
    E:w('else')
    self:push_scope()
    self:block(s.else_body, sink)
    self:pop_scope()
  end
  E:sp()
  E:w(tmp and 'end end' or 'end')
end

function Compiler:lower_with(s, sink)
  local E = self.E
  local var = self:tmp('with')
  E:stmt(s.line)
  E:w('do local ' .. var .. ' = ')
  self:expr(s.target)
  self.with_stack[#self.with_stack + 1] = var
  -- the value of a with block is its target, which code after the body passes on
  local passes_value = sink and sink.k ~= 'discard'
  self:push_scope()
  self:block(s.body, nil, passes_value, passes_value)
  self:pop_scope()
  self.with_stack[#self.with_stack] = nil
  if passes_value then
    self:apply(sink, { raw(var) })
  end
  E:sp()
  E:w('end')
end

function Compiler:stmt_Do(s, sink)
  local E = self.E
  E:stmt(s.line)
  E:w('do')
  self:push_scope()
  self:block(s.body, sink)
  self:pop_scope()
  E:sp()
  E:w('end')
end

-- n when e is a negative number literal, -n.
local function negative_literal(e)
  if e.k == 'Unop' and e.op == '-' and e.e.k == 'Number' then
    local n = tonumber(e.e.v)
    if n and n > 0 then return n end
  end
end

-- The index k before the end of `list`, #list - k.
local function from_end(list, k)
  if k == 0 then return '#' .. list end
  return '#' .. list .. ' - ' .. (k == math.floor(k) and format('%d', k) or tostring(k))
end

-- Emits the head of a loop or comprehension clause, up to and including its 'do',
-- binding the loop variables. `assigned` holds the names that the loop assigns, of
-- which the loop variables get copies (see assigned_loop_vars). Returns how many
-- 'end's close it.
function Compiler:loop_head(s, assigned)
  local E = self.E

  if s.k == 'For' then
    local var = s.var
    local control = assigned and assigned[var] and self:tmp('i') or var
    E:w('for ' .. control .. ' = ')
    self:expr(s.start)
    E:w(', ')
    self:expr(s.stop)
    if s.step then
      E:w(', ')
      self:expr(s.step)
    end
    E:w(' do')
    if control ~= var then E:w(' local ' .. var .. ' = ' .. control) end
    self:bind(var, s.var_tok, 'loop variable')
    return 1
  elseif s.k == 'While' then
    E:w('while ')
    self:expr(s.cond)
    E:w(' do')
    return 1
  end

  if s.star then
    local list, i = self:tmp('list'), self:tmp('i')
    local star, start, stop, step = s.star, nil, nil, nil
    if star.k == 'Slice' then
      start, stop, step, star = star.start, star.stop, star.step, star.obj
    end
    -- a negative step can't go anywhere from the defaults, start 1 and stop #list
    if step and negative_literal(step) and not (start and stop) then
      self:error('a negative step needs a start and a stop, as in *t[-1, 1, -1]', step)
    end
    E:w('do local ' .. list .. ' = ')
    self:expr(star)
    -- A negative start or stop counts from the end, as in Python: -n starts at the
    -- n-th value from the end, #list + 1 - n, and stops n values before the end,
    -- #list - n. Literals are worked out here, and other values when the loop starts.
    local start_n, stop_n = start and negative_literal(start), stop and negative_literal(stop)
    local min, max
    if start and start.k ~= 'Number' and not start_n then
      min = self:tmp('min')
      E:w('; local ' .. min .. ' = ')
      self:expr(start)
    end
    if stop and stop.k ~= 'Number' and not stop_n then
      max = self:tmp('max')
      E:w('; local ' .. max .. ' = ')
      self:expr(stop)
    end
    E:w('; for ' .. i .. ' = ')
    if min then
      E:w(format('%s < 0 and #%s + 1 + %s or %s', min, list, min, min))
    elseif start_n then
      E:w(from_end(list, start_n - 1))
    elseif start then
      self:expr(start)
    else
      E:w('1')
    end
    E:w(', ')
    if max then
      E:w(format('%s < 0 and #%s + %s or %s', max, list, max, max))
    elseif stop_n then
      E:w(from_end(list, stop_n))
    elseif stop then
      self:expr(stop)
    else
      E:w('#' .. list)
    end
    if step then
      E:w(', ')
      self:expr(step)
    end
    E:w(' do')
    local var = s.vars[1]
    local item = list .. '[' .. i .. ']'
    if var.k == 'Pattern' then
      self:bind_pattern(var, raw(item))
    else
      E:w(' local ' .. var.v .. ' = ' .. item)
      self:bind(var.v, var, 'loop variable')
    end
    return 2
  end

  local names, patterns = {}, {}
  for i, var in ipairs(s.vars) do
    if var.k == 'Pattern' or (assigned and assigned[var.v]) then
      names[i] = self:tmp('item')
    else
      names[i] = var.v
    end
    if var.k == 'Pattern' then patterns[#patterns + 1] = { var, names[i] } end
  end
  E:w('for ' .. concat(names, ', ') .. ' in ')
  self:expr_list(s.exprs)
  E:w(' do')
  for i, var in ipairs(s.vars) do
    if var.k == 'Name' then
      if names[i] ~= var.v then E:w(' local ' .. var.v .. ' = ' .. names[i]) end
      self:bind(var.v, var, 'loop variable')
    end
  end
  for _, p in ipairs(patterns) do
    self:bind_pattern(p[1], raw(p[2]))
  end
  return 1
end

-- Raises the error for the new name `t` declared in a loop body, by an update when
-- `update` is set.
function Compiler:per_iteration_error(t, update)
  local hint = update
    and "give it a value before the loop, which the loop then updates"
    or format("declare it before the loop with 'local %s'", t.v)
  self:error(format("'%s' would be a new local of each iteration, gone after it; %s",
    t.v, hint), t, #t.v)
end

-- The statement of a `for` modifier is the loop's body, so a name it declared would
-- be a local of each iteration, gone after it. `stmt` may be wrapped in the if of
-- the modifier's filter.
function Compiler:no_new_names(stmt)
  if stmt.k == 'If' and not stmt.decorator then stmt = stmt.bodies[1][1] end
  local targets = stmt.k == 'Assign' and stmt.targets or stmt.k == 'Update' and { stmt.target }
  local function check(t)
    if t.k == 'Name' and self.scope:is_fresh(t.v) then
      self:per_iteration_error(t, stmt.k == 'Update')
    elseif t.k == 'Pattern' then
      for _, entry in ipairs(t.entries) do check(entry.target) end
    end
  end
  for _, t in ipairs(targets or {}) do check(t) end
end

function Compiler:loop(s)
  local E = self.E
  local loop = { label = has_continue(s.body) and self:tmp('continue') or nil }
  E:stmt(s.line)
  self:push_scope()
  local closes = self:loop_head(s, assigned_loop_vars(s.body, self.target))
  if s.modifier then self:no_new_names(s.body[1]) end
  local saved = self.fn.loop
  self.fn.loop = loop
  self:block(s.body, nil, loop.label ~= nil)
  self.fn.loop = saved
  if loop.label then
    -- a label ending the body is outside the scope of the body's locals, so the
    -- gotos can jump past them
    E:sp()
    E:w('::' .. loop.label .. '::')
  end
  for _ = 1, closes do
    E:sp()
    E:w('end')
  end
  self:pop_scope()
end

function Compiler:lower_comprehension(c, sink)
  local E = self.E
  local acc = self:tmp('acc')
  local n = c.kind == 'list' and self:tmp('n')
  E:stmt(c.line)
  E:w('do local ' .. acc .. (n and (', ' .. n .. ' = {}, 0') or ' = {}'))
  self:push_scope()

  local closes = 0
  local assigned = assigned_loop_vars(c, self.target)
  for _, clause in ipairs(c.clauses) do
    E:sp(clause.line)
    if clause.k == 'filter' then
      E:w(clause.unless and 'if not ' or 'if ')
      self:expr(clause.cond, clause.unless and UNARY or nil)
      E:w(' then')
      closes = closes + 1
    else
      closes = closes + self:loop_head(clause, assigned)
    end
  end

  -- comprehensions in the element are hoisted into the loop's body
  if n then
    local function emit(exprs)
      E:stmt(c.expr.line)
      E:w(format('%s = %s + 1; %s[%s] = ', n, n, acc, n))
      self:expr(exprs[1])
    end
    if not self:hoist(c.expr.line, { c.expr }, nil, emit) then emit({ c.expr }) end
  elseif c.vexpr then
    local function emit(exprs)
      E:stmt(c.kexpr.line)
      E:w(acc .. '[')
      self:expr(exprs[1])
      E:w('] = ')
      self:expr(exprs[2])
    end
    if not self:hoist(c.kexpr.line, { c.kexpr, c.vexpr }, nil, emit) then
      emit({ c.kexpr, c.vexpr })
    end
  else
    -- a single expression gives both the key and the value, which only calls and
    -- ... can; another would set each key to nil, which sets nothing
    if not multi_valued[c.kexpr.k] then
      self:error("a table comprehension's one expression gives the key and the value, but this one gives a single value, so it would set nothing; write {k, v for ...}, or [x for ...] for a list", c.kexpr)
    end
    local k, v = self:tmp('k'), self:tmp('v')
    E:stmt(c.kexpr.line)
    E:w('local ' .. k .. ', ' .. v .. ' = ')
    self:expr(c.kexpr)
    E:w(format('; %s[%s] = %s', acc, k, v))
  end

  for _ = 1, closes do
    E:sp()
    E:w('end')
  end
  self:pop_scope()
  self:apply(sink, { raw(acc) })
  E:sp()
  E:w('end')
end

-- Comprehensions inside an expression are hoisted out of it where they can be: the
-- statement becomes a `do` block computing them into locals first, so they don't
-- compile to a function called in place, which costs a closure each time and stops
-- LuaJIT from compiling the loop around it. Everything the statement evaluates
-- before such a comprehension is computed into a local before it too, in order, so
-- that the order of evaluation stays as it was:
--
--   f(x, [y for y in *t])  ->  do local __hs_s1 = f; local __hs_s2 = x;
--                                local __hs_v3 do ... end; __hs_s1(__hs_s2, __hs_v3) end
--
-- A comprehension is hoisted when it's all on the statement's line, which keeps the
-- statement on its line, and when it's always evaluated: not on the right of `and`
-- or `or`, nor inside a function, a string's interpolation or another value block.
-- Others stay functions called in place, and so do `with` blocks, which span lines.

-- Expressions that stay as they are, as nothing evaluated after them can change
-- their value: literals, functions (whose body runs later) and super.
local unchanging = {
  Nil = true, True = true, False = true, Number = true, Func = true, Raw = true,
  Super = true,
}

-- Whether all of node `e` is on `line`.
local function on_line(e, line)
  if e.line and e.line ~= line then return false end
  for _, v in pairs(e) do
    if type(v) == 'table' and not on_line(v, line) then return false end
  end
  return true
end

-- Whether node `e` refers to one of `names` anywhere inside it.
local function mentions(e, names)
  if e.k == 'Name' and names[e.v] then return true end
  for _, v in pairs(e) do
    if type(v) == 'table' and mentions(v, names) then return true end
  end
  return false
end

-- Counts the names, fields and methods of node `e` by their names, into `counts`.
local function count_names(e, counts)
  local name = e.k == 'Name' and e.v
    or (e.k == 'Field' or e.k == 'SelfField' or e.k == 'ClassField' or e.k == 'MethodCall'
      or e.k == 'WithCall' or e.k == 'WithField') and e.name
  if type(name) == 'string' then counts[name] = (counts[name] or 0) + 1 end
  for _, v in pairs(e) do
    if type(v) == 'table' then count_names(v, counts) end
  end
  return counts
end

-- Finds the comprehensions of `e` that can be hoisted to a statement on `line`,
-- adding them to `found`, and marking in `on_path` the nodes containing one.
-- Returns whether `e` contains one.
local function find_hoistable(e, line, found, on_path)
  local k = e.k
  local inside = false
  local function sub(x)
    if x and find_hoistable(x, line, found, on_path) then inside = true end
  end
  if k == 'Comprehension' then
    if on_line(e, line) then
      found[e] = true
      return true
    end
  elseif k == 'Call' then
    if e.fn.k ~= 'Super' then sub(e.fn) end
    for _, a in ipairs(e.args) do sub(a) end
  elseif k == 'MethodCall' then
    if e.obj.k ~= 'Super' then sub(e.obj) end
    for _, a in ipairs(e.args) do sub(a) end
  elseif k == 'WithCall' then
    for _, a in ipairs(e.args) do sub(a) end
  elseif k == 'Binop' then
    sub(e.l)
    -- the right of and and or is evaluated only sometimes
    if e.op ~= 'and' and e.op ~= 'or' then sub(e.r) end
  elseif k == 'IsA' then
    sub(e.obj)
    sub(e.cls)
  elseif k == 'Unop' or k == 'Paren' then
    sub(e.e)
  elseif k == 'Field' then
    sub(e.obj)
  elseif k == 'Index' then
    sub(e.obj)
    sub(e.key)
  elseif k == 'Table' then
    for _, entry in ipairs(e.entries) do
      if entry.k == 'expr' then sub(entry.key) end
      sub(entry.v)
    end
  end
  if inside then on_path[e] = true end
  return inside
end

-- Compiles a statement evaluating `exprs`, hoisting their comprehensions where it
-- can (see above), and returns whether it did. `fresh` names the new locals the
-- statement declares, declared before its `do` block, `assigned` the names it
-- assigns, and `emit(exprs)` writes the statement with the hoisted parts replaced.
function Compiler:hoist(line, exprs, fresh, emit, assigned)
  local found, on_path, any = {}, {}, false
  for _, e in ipairs(exprs) do
    if find_hoistable(e, line, found, on_path) then any = true end
  end
  if not any then return false end
  if fresh and #fresh > 0 then
    -- the hoisted parts would see the new locals rather than what the names were
    local names = {}
    for _, name in ipairs(fresh) do names[name] = true end
    for _, e in ipairs(exprs) do
      if mentions(e, names) then return false end
    end
  end

  local E = self.E
  local remaining = 0
  for _ in pairs(found) do remaining = remaining + 1 end

  -- A local holding a name, field or method gets its name where nothing else in the
  -- statement has it, so that Lua's errors, such as calling nil, name it.
  local counts, used = {}, {}
  for _, e in ipairs(exprs) do count_names(e, counts) end
  -- a local of an assigned name would take the assignment
  for _, name in ipairs(assigned or {}) do used[name] = true end
  local function temp_for(name)
    if type(name) == 'string' and counts[name] == 1 and not used[name]
      and valid_name(name) and name ~= 'self' then
      used[name] = true
      return name
    end
    return self:tmp('s')
  end

  local rewrite
  local function list(nodes)
    local out = {}
    for i, n in ipairs(nodes) do out[i] = rewrite(n) end
    return out
  end
  local function copy(e, changes)
    local c = {}
    for k, v in pairs(e) do c[k] = v end
    for k, v in pairs(changes) do c[k] = v end
    return c
  end
  -- the value of `e`, evaluated into a local now
  local function spill(e)
    local k = e.k
    local tmp = temp_for(k == 'Name' and e.v
      or (k == 'Field' or k == 'SelfField' or k == 'ClassField') and e.name)
    E:stmt()
    E:w('local ' .. tmp .. ' = ')
    self:expr(e)
    return raw(tmp)
  end
  rewrite = function(e)
    if remaining == 0 then return e end
    if found[e] then
      remaining = remaining - 1
      local tmp = self:tmp('v')
      E:stmt()
      E:w('local ' .. tmp)
      self:lower(e, { k = 'assign', targets = { raw(tmp) } })
      return raw(tmp)
    end
    if not on_path[e] then
      return unchanging[e.k] and e or spill(e)
    end
    local k, n = e.k, nil
    if k == 'Call' then
      local fn = e.fn.k == 'Super' and e.fn or rewrite(e.fn)
      n = copy(e, { fn = fn, args = list(e.args) })
    elseif k == 'MethodCall' and e.obj.k == 'Super' then
      n = copy(e, { args = list(e.args) })
    elseif k == 'MethodCall' or k == 'WithCall' then
      -- the method is looked up before the arguments are evaluated
      local obj = k == 'WithCall' and raw(self:with_var(e)) or rewrite(e.obj)
      if not is_simple(obj) then obj = spill(obj) end
      local method = temp_for(e.name)
      E:stmt()
      E:w('local ' .. method .. ' = ')
      self:prefix(obj)
      E:w(field(e.name))
      local args = list(e.args)
      table.insert(args, 1, obj)
      n = { k = 'Call', fn = raw(method), args = args, line = e.line }
    elseif k == 'Binop' then
      local l = rewrite(e.l)
      -- the right of and and or stays where it's evaluated only sometimes
      n = (e.op == 'and' or e.op == 'or') and copy(e, { l = l })
        or copy(e, { l = l, r = rewrite(e.r) })
    elseif k == 'IsA' then
      local obj = rewrite(e.obj)
      n = copy(e, { obj = obj, cls = rewrite(e.cls) })
    elseif k == 'Unop' or k == 'Paren' then
      n = copy(e, { e = rewrite(e.e) })
    elseif k == 'Field' then
      n = copy(e, { obj = rewrite(e.obj) })
    elseif k == 'Index' then
      local obj = rewrite(e.obj)
      n = copy(e, { obj = obj, key = rewrite(e.key) })
    elseif k == 'Table' then
      local entries = {}
      for i, entry in ipairs(e.entries) do
        local key = entry.k == 'expr' and rewrite(entry.key) or entry.key
        entries[i] = copy(entry, { key = key, v = rewrite(entry.v) })
      end
      n = copy(e, { entries = entries })
    else
      error('hoisting through ' .. k)
    end
    -- evaluated now when comprehensions after it are hoisted, to keep the order
    return remaining > 0 and spill(n) or n
  end

  E:stmt(line)
  if fresh and #fresh > 0 then
    E:w('local ' .. concat(fresh, ', ') .. '; ')
  end
  E:w('do')
  local new = list(exprs)
  emit(new)
  E:sp()
  E:w('end')
  return true
end

-- A value block inside an expression, as an immediately called function.
function Compiler:iife(e)
  local E = self.E
  local vararg = self.fn.vararg
  E:w(vararg and '(function(...)' or '(function()')
  local saved = self.fn
  self.fn = { vararg = vararg, iife = true, parent = saved }
  self:push_scope()
  self:lower(e, { k = 'return' })
  self:pop_scope()
  self.fn = saved
  E:sp()
  E:w(vararg and 'end)(...)' or 'end)()')
end

-- Statements

function Compiler:stmt_ExprStmt(s)
  local e = s.exprs[1]
  if #s.exprs > 1 then
    self:error('a list of values can only be the last statement of a function, which returns it', s.exprs[2])
  end
  if value_blocks[e.k] then
    return self:lower(e, DISCARD)
  end
  if not calls[e.k] then
    self:error('this expression does nothing; only calls can be statements', e)
  end
  if self:hoist(s.line, s.exprs, nil, function(exprs)
    self.E:stmt()
    self:expr(exprs[1])
  end) then
    return
  end
  self.E:stmt(s.line)
  self:expr(e)
end

-- Checks the attributes of a statement declaring `n` names (see attribs in
-- parser.lua): `<close>` needs a Lua that has it, and Lua takes one per statement.
-- Returns the attribute names by the name they're declared for.
function Compiler:check_attribs(attribs, names)
  local consts, close = {}, nil
  for i = 1, #names do
    local a = attribs[i]
    if a then
      consts[names[i]] = a.v
      if a.v == 'close' then
        if not self.target.close then
          self:error("'<close>' needs Lua 5.4 or later, and this compiles for a Lua without it; compile for a target that has it", a, #a.v)
        end
        if close then
          self:error("only one name of a statement can be '<close>', as in Lua", a, #a.v)
        end
        close = a
      end
    end
  end
  return consts
end

-- Marks the locals of `names` that `consts` has as constants.
function Compiler:mark_consts(names, consts)
  for _, name in ipairs(names) do
    if consts[name] then self.scope.names[name].const = consts[name] end
  end
end

-- An assignment to the visible local `t`, which may not be a constant, or a class
-- body's self, through which the body writes the class.
function Compiler:check_not_const(t)
  local decl = self.scope:lookup(t.v)
  if decl and decl.const then
    self:error(format("'%s' is a constant, declared with <%s> on line %d", t.v, decl.const, decl.line), t, #t.v)
  end
  if decl and decl.class then
    self:error("'self' is the class in a class body, and can't be assigned", t, 4)
  end
end

-- An assignment declaring names with attributes, `lock <close> = Lock()`. All its
-- targets are names, which it must declare. A `<close>` goes in the Lua, after
-- the value, while `<const>` is checked by the compiler alone, so its names follow
-- the rules of other assignments.
function Compiler:assign_attributed(s)
  local E = self.E
  local names, seen = {}, {}
  for i, t in ipairs(s.targets) do
    self:check_name(t.v, t)
    if not self.scope:is_fresh(t.v) or seen[t.v] then
      self:error(format(
        "'%s' is already a local, so this doesn't declare it, as a statement with '<const>' or '<close>' must; use another name",
        t.v), t, #t.v)
    end
    seen[t.v] = true
    names[i] = t.v
  end
  local consts = self:check_attribs(s.attribs, names)
  local has_close = false
  for _, kind in pairs(consts) do
    if kind == 'close' then has_close = true end
  end
  if not has_close then
    return self:stmt_Assign(s, consts)
  end

  local declared = {}
  for i, name in ipairs(names) do
    declared[i] = consts[name] == 'close' and (name .. ' <close>') or name
  end
  local values = s.values
  E:stmt(s.line)
  if #values == 1 and value_blocks[values[1].k] then
    -- the block assigns its value to a temporary, which then declares the local
    local tmp = self:tmp('value')
    E:w('local ' .. tmp)
    self:lower(values[1], { k = 'assign', targets = { raw(tmp) } })
    E:w(' local ' .. concat(declared, ', ') .. ' = ' .. tmp)
  else
    E:w('local ' .. concat(declared, ', ') .. ' = ')
    self:expr_list(values)
  end
  self:declare_all(names, s.line)
  self:mark_consts(names, consts)
end

-- `consts`, for an assignment declaring constants, has their attributes by name.
function Compiler:stmt_Assign(s, consts)
  local E = self.E
  if s.attribs and not consts then return self:assign_attributed(s) end
  consts = consts or {}
  for _, t in ipairs(s.targets) do
    if t.k == 'Pattern' then return self:destructure(s) end
  end

  local fresh, seen = {}, {}
  local all_fresh = true
  for _, t in ipairs(s.targets) do
    if t.k == 'Name' then
      self:check_name(t.v, t)
      if self.scope:is_fresh(t.v) and not seen[t.v] then
        fresh[#fresh + 1] = t.v
        seen[t.v] = true
      else
        self:check_not_const(t)
        all_fresh = false
      end
    else
      all_fresh = false
    end
  end

  local values = s.values

  -- The new names are visible in their own value when it's a
  -- with block or a comprehension, or when one of the values is a function, which
  -- can then call itself. Otherwise they're visible after the statement, so
  -- `x = x + 1` reads the global x.
  local block = #values == 1 and value_blocks[values[1].k]
  local func = false
  for _, v in ipairs(values) do
    if v.k == 'Func' then func = true end
  end

  local names_only, assigned = not s.attribs, {}
  for i, t in ipairs(s.targets) do
    if t.k ~= 'Name' then names_only = false end
    assigned[i] = t.v
  end
  if names_only and not block and not func and self:hoist(s.line, values, fresh, function(exprs)
    E:stmt()
    self:targets(s.targets)
    E:w(' = ')
    self:expr_list(exprs)
  end, assigned) then
    self:declare_all(fresh, s.line)
    return
  end

  E:stmt(s.line)
  if block or func then
    local decls = {}
    if #fresh > 0 then
      E:w('local ' .. concat(fresh, ', ') .. (block and '' or '; '))
      for i, name in ipairs(fresh) do
        -- parameters and loop variables in the value may still use the name, and
        -- functions in it may read it (see e_Name)
        decls[i] = self.scope:declare(name, s.line)
        decls[i].assigning = self.fn
        decls[i].const = consts[name]
      end
    end
    if block then
      self:lower(values[1], { k = 'assign', targets = s.targets })
    else
      self:targets(s.targets)
      E:w(' = ')
      self:expr_list(values)
    end
    for _, decl in ipairs(decls) do decl.assigning = nil end
    return
  end

  if all_fresh then
    E:w('local ')
  elseif #fresh > 0 then
    E:w('local ' .. concat(fresh, ', ') .. '; ')
  end
  self:targets(s.targets)
  E:w(' = ')
  self:expr_list(values)
  -- names are visible after the statement, not in its own right-hand side
  self:declare_all(fresh, s.line)
  self:mark_consts(fresh, consts)
end

function Compiler:targets(list)
  for i, t in ipairs(list) do
    if i > 1 then self.E:w(', ') end
    if t.k == 'Name' then
      -- written, not read, so not an e_Name
      self:check_name(t.v, t)
      self.E:w(t.v)
    else
      self:expr(t)
    end
  end
end

-- Collects what a pattern assigns as { target, value } pairs, with values reading
-- from `base`.
function Compiler:collect_leaves(pattern, base, out)
  local pos = 0
  for _, entry in ipairs(pattern.entries) do
    local access
    if entry.k == 'pos' then
      pos = pos + 1
      access = { k = 'Index', obj = base, key = { k = 'Number', v = tostring(pos) } }
    elseif entry.k == 'named' then
      access = { k = 'Field', obj = base, name = entry.key }
    else
      access = { k = 'Index', obj = base, key = entry.key }
    end
    if entry.target.k == 'Pattern' then
      self:collect_leaves(entry.target, access, out)
    else
      out[#out + 1] = { target = entry.target, value = access }
    end
  end
  return out
end

-- Declares the names in a loop variable's pattern as new locals, and assigns them
-- from `base`.
function Compiler:bind_pattern(pattern, base)
  local E = self.E
  local leaves = self:collect_leaves(pattern, base, {})
  local names = {}
  for i, leaf in ipairs(leaves) do
    if leaf.target.k ~= 'Name' then
      self:error('only names can be bound by a loop variable', leaf.target)
    end
    names[i] = leaf.target.v
  end
  E:stmt()
  E:w('local ' .. concat(names, ', ') .. ' = ')
  for i, leaf in ipairs(leaves) do
    if i > 1 then E:w(', ') end
    self:expr(leaf.value)
  end
  for i, leaf in ipairs(leaves) do
    self:bind(names[i], leaf.target, 'loop variable')
  end
end

function Compiler:destructure(s)
  local E = self.E
  local targets, values = s.targets, s.values
  local fresh, seen = {}, {}
  local all_fresh = true

  local function note(t)
    if t.k == 'Name' then
      self:check_name(t.v, t)
      if self.scope:is_fresh(t.v) and not seen[t.v] then
        fresh[#fresh + 1] = t.v
        seen[t.v] = true
        return
      end
      self:check_not_const(t)
    end
    all_fresh = false
  end

  E:stmt(s.line)

  -- a single pattern taking apart a plain lookup reads from it directly
  if #targets == 1 and #values == 1 and is_path(values[1]) then
    local leaves = self:collect_leaves(targets[1], values[1], {})
    for _, leaf in ipairs(leaves) do note(leaf.target) end
    if all_fresh then
      E:w('local ')
    elseif #fresh > 0 then
      E:w('local ' .. concat(fresh, ', ') .. '; ')
    end
    for i, leaf in ipairs(leaves) do
      if i > 1 then E:w(', ') end
      self:targets({ leaf.target })
    end
    E:w(' = ')
    for i, leaf in ipairs(leaves) do
      if i > 1 then E:w(', ') end
      self:expr(leaf.value)
    end
    self:declare_all(fresh, s.line)
    return
  end

  -- otherwise the values are evaluated into temporaries first
  local lua_targets, leaves, tmps = {}, {}, {}
  for i, t in ipairs(targets) do
    if t.k == 'Pattern' then
      local tmp = self:tmp('obj')
      tmps[#tmps + 1] = tmp
      lua_targets[i] = raw(tmp)
      self:collect_leaves(t, raw(tmp), leaves)
    else
      lua_targets[i] = t
      note(t)
    end
  end
  for _, leaf in ipairs(leaves) do note(leaf.target) end

  if #fresh > 0 then
    E:w('local ' .. concat(fresh, ', ') .. '; ')
  end
  if #targets == 1 then
    E:w('do local ' .. tmps[1] .. ' = ')
  else
    E:w('do local ' .. concat(tmps, ', ') .. '; ')
    self:targets(lua_targets)
    E:w(' = ')
  end
  self:expr_list(values)
  E:w('; ')
  for i, leaf in ipairs(leaves) do
    if i > 1 then E:w(', ') end
    self:targets({ leaf.target })
  end
  E:w(' = ')
  for i, leaf in ipairs(leaves) do
    if i > 1 then E:w(', ') end
    self:expr(leaf.value)
  end
  E:w(' end')
  self:declare_all(fresh, s.line)
end

function Compiler:stmt_Update(s)
  local E = self.E
  local target = s.target
  if target.k == 'Name' and not self.scope:is_fresh(target.v) then
    self:check_name(target.v, target)
    self:check_not_const(target)
    local value = { k = 'Binop', op = s.op, l = target, r = s.value, op_tok = s.op_tok, line = s.line }
    if self:hoist(s.line, { value }, nil, function(exprs)
      E:stmt()
      E:w(target.v .. ' = ')
      self:expr(exprs[1])
    end, { target.v }) then
      return
    end
  end
  E:stmt(s.line)

  -- receivers and keys with side effects are evaluated once
  local names, values = {}, {}
  local function once(e)
    if is_simple(e) then return e end
    local name = self:tmp('ref')
    names[#names + 1] = name
    values[#values + 1] = e
    return raw(name)
  end

  local t = target
  if target.k == 'Name' then
    self:check_name(target.v, target)
    -- like any first assignment, it declares a local: `local x = x + 1`, where the
    -- right-hand side still sees the outer x
    if self.scope:is_fresh(target.v) then
      -- in a loop, that's a new local updating the outer x on each iteration
      if self.fn.loop then self:per_iteration_error(target, true) end
      E:w('local ' .. target.v .. ' = ')
      self:expr({ k = 'Binop', op = s.op, l = target, r = s.value, op_tok = s.op_tok })
      self.scope:declare(target.v, s.line)
      return
    end
    self:check_not_const(target)
  elseif target.k == 'Field' and target.obj.k ~= 'Super' then
    t = { k = 'Field', obj = once(target.obj), name = target.name, line = target.line }
  elseif target.k == 'Index' then
    t = { k = 'Index', obj = once(target.obj), key = once(target.key), line = target.line }
  end

  if #names > 0 then
    E:w('do local ' .. concat(names, ', ') .. ' = ')
    self:expr_list(values)
    E:w('; ')
  end
  self:expr(t)
  E:w(' = ')
  self:expr({ k = 'Binop', op = s.op, l = t, r = s.value, op_tok = s.op_tok })
  if #names > 0 then E:w(' end') end
end

function Compiler:stmt_Return(s, wrap)
  local E = self.E
  if self.fn.iife then
    self:error("'return' can't be used here, as the expression it's in is compiled to a function; assign the expression to a variable first", s)
  end
  local values = s.values
  if #values == 1 and value_blocks[values[1].k] then
    return self:lower(values[1], { k = 'return' })
  end
  -- in the do block hoisting makes, the return is last as Lua needs
  if self:hoist(s.line, values, nil, function(exprs)
    E:stmt()
    E:w('return ')
    self:expr_list(exprs)
  end) then
    return
  end
  E:stmt(s.line)
  E:w(wrap and 'do return' or 'return')
  if #values > 0 then
    E:w(' ')
    self:expr_list(values)
  end
  if wrap then E:w(' end') end
end

function Compiler:loop_for(s, what)
  local loop = self.fn.loop
  if not loop then
    if self.fn.iife then
      self:error(format(
        "'%s' can't be used here, as the expression it's in is compiled to a function; assign the expression to a variable first",
        what), s)
    end
    self:error(format("'%s' outside of a loop", what), s)
  end
  return loop
end

function Compiler:stmt_Break(s, wrap)
  self:loop_for(s, 'break')
  self.E:stmt(s.line)
  self.E:w(wrap and 'do break end' or 'break')
end

function Compiler:stmt_Continue(s)
  local loop = self:loop_for(s, 'continue')
  self.E:stmt(s.line)
  self.E:w('goto ' .. loop.label)
end

function Compiler:stmt_Local(s)
  local E = self.E
  local names = {}
  for i, n in ipairs(s.names) do
    self:check_name(n.v, n)
    local decl = n.v == 'self' and self.scope:lookup('self')
    if decl and decl.class then
      self:error("'self' is the class in a class body, and can't be declared again", n, 4)
    end
    names[i] = n.v
  end
  local consts = s.attribs and self:check_attribs(s.attribs, names) or {}
  local declared = {}
  for i, name in ipairs(names) do
    declared[i] = consts[name] == 'close' and (name .. ' <close>') or name
  end
  E:stmt(s.line)
  E:w('local ' .. concat(declared, ', '))
  if s.values then
    E:w(' = ')
    self:expr_list(s.values)
  end
  self:declare_all(names, s.line)
  self:mark_consts(names, consts)
end

function Compiler:stmt_With(s) self:lower_with(s, DISCARD) end
function Compiler:stmt_For(s) self:loop(s) end
function Compiler:stmt_ForIn(s) self:loop(s) end
function Compiler:stmt_While(s) self:loop(s) end

-- Assigned names in a class body are locals of the class body, declared up front
-- so that every method sees them. Returns them, and the lines assigning them by name.
local function class_locals(body, scope)
  local names, lines = {}, {}
  local function add(t, line)
    if t.k == 'Name' and not lines[t.v] and scope:is_fresh(t.v) then
      names[#names + 1] = t.v
      lines[t.v] = line
    elseif t.k == 'Pattern' then
      for _, entry in ipairs(t.entries) do add(entry.target, line) end
    end
  end
  for _, item in ipairs(body) do
    if item.k == 'Assign' then
      for _, t in ipairs(item.targets) do add(t, item.line) end
    end
  end
  return names, lines
end

-- Marks the names among `targets` as assigned (see Compiler:e_Name).
function Compiler:assigned(targets)
  for _, t in ipairs(targets) do
    if t.k == 'Name' then
      local decl = self.scope:lookup(t.v)
      if decl then decl.unassigned = nil end
    elseif t.k == 'Pattern' then
      local nested = {}
      for i, entry in ipairs(t.entries) do nested[i] = entry.target end
      self:assigned(nested)
    end
  end
end

-- The name a member's key gives, when it's a name or a plain string.
local function key_name(key)
  if type(key) == 'string' then return key end
  if key.k == 'String' and #key.parts == 1 and type(key.parts[1]) == 'string' then
    return key.parts[1]
  end
end

local function is_fallback(name)
  return name == '__index' or name == '__newindex'
end

-- The name of an entry in a class's `meta`, when it's keyed by a name or a string.
local function meta_name(entry)
  if entry.k == 'named' then return entry.key end
  if entry.k == 'expr' then return key_name(entry.key) end
end

-- Checks a class's `meta`, returning whether it has fallbacks.
function Compiler:check_meta(item)
  local given, fallbacks = {}, false
  for _, entry in ipairs(item.entries) do
    local name = meta_name(entry)
    if not name then
      self:error("'meta' takes metamethods by name, as in 'meta {__tostring: => ...}'", entry)
    end
    if not (is_metamethod[name] or is_meta_field[name] or is_fallback(name)) then
      self:error(format("'%s' isn't one of Lua's metamethods", name), entry, #name)
    end
    if given[name] then
      self:error(format("'%s' is given twice in 'meta'", name), entry, #name)
    end
    given[name] = true
    fallbacks = fallbacks or is_fallback(name)
  end
  return fallbacks
end

-- Writes a member of the class being compiled, keyed by a name or an expression.
function Compiler:class_member(line, key, value)
  local E, cls = self.E, self.cls
  local b, p = cls.b, cls.p
  E:stmt(line)
  local is_new = key == 'new'
  if is_new then
    E:w('self.__init = ')
  elseif type(key) == 'string' then
    E:w(p and format('%s(%s, %q, ', self:global('rawset'), b, key) or (b .. field(key) .. ' = '))
  else
    E:w(p and (self:global('rawset') .. '(' .. b .. ', ') or (b .. '['))
    self:expr(key)
    E:w(p and ', ' or '] = ')
  end
  cls.method = key
  if value.k == 'Func' then
    -- constructors return nothing
    self:func(value, is_new)
  else
    self:expr(value)
  end
  cls.method = nil
  if p and not is_new then E:w(')') end
end

-- Classes are laid out as REFERENCE.md's Layout section says. The body runs top to
-- bottom, which keeps the lines aligned; since the base may then already have a
-- parent with a __newindex, members are added with rawset.
--
-- Classes with a parent, properties, fallbacks or metamethods use the runtime
-- support in CLASS_SUPPORT, which extends that layout.
--
-- The class is assigned to its name at the class line, and the body refers to it as
-- `self`, which it can't assign (see check_not_const). Its other names live in the
-- class's `do` block, so they need no numbers: the parent is evaluated first, as
-- `super` in the parent expression of a class nested in a method refers to the
-- outer `__hs_parent`.
function Compiler:stmt_Class(s)
  local E = self.E
  local name = s.name
  self:check_name(name, s.name_tok)
  local b, p = '__hs_base', s.parent and '__hs_parent'

  -- own: whether the class has properties or fallbacks of its own, which make it
  -- dispatch even without a parent that does
  local own, has_properties, support = false, false, p ~= nil
  local meta_line
  for _, item in ipairs(s.body) do
    if item.k == 'accessor' then
      own, has_properties = true, true
    elseif item.k == 'meta' then
      if meta_line then
        self:error(format("'meta' is already given on line %d of this class", meta_line), item, 4)
      end
      meta_line = item.line
      own = self:check_meta(item) or own
      support = support or #item.entries > 0
    elseif item.k == 'prop' then
      local kn = key_name(item.key)
      if is_metamethod[kn] or is_meta_field[kn] or is_fallback(kn) then
        self:error(format("'%s' goes in the metatable; write 'meta {%s: ...}'", kn, kn), item, #kn)
      end
    end
  end
  support = support or own
  local props = has_properties and '__hs_props'

  E:stmt(s.line)
  if self.scope:is_fresh(name) then
    E:w('local ' .. name .. '; ')
    self.scope:declare(name, s.line)
  else
    self:check_not_const({ v = name, line = s.name_tok.line, col = s.name_tok.col })
  end
  E:w('do ')
  if p then
    E:w('local ' .. p .. ' = ')
    self:expr(s.parent)
    E:w('; ')
  end
  -- the instances' __name is the class's name, which Lua 5.3+ shows in tostring
  E:w(format('local %s = {__name = %q}; %s.__index = %s', b, name, b, b))

  self:push_scope()
  -- declared before the body's locals, so that assigning self is an error rather
  -- than a new local
  self.scope:declare('self', s.line).class = true
  local locals, assigning_lines = class_locals(s.body, self.scope)
  if #locals > 0 then
    E:w('; local ' .. concat(locals, ', '))
    self:declare_all(locals, s.line)
    -- nil until their assignments run, so until then only functions may read them
    for _, name in ipairs(locals) do
      local decl = self.scope.names[name]
      decl.unassigned, decl.assigned_on = self.fn, assigning_lines[name]
    end
  end

  local init = p and format('function(self, ...) return %s.__init(self, ...) end', p)
    or 'function() end'
  local index = p and format(
    'function(_, name) local val = %s(%s, name); if val == nil then return %s[name] end return val end',
    self:global('rawget'), b, p) or b
  local setmetatable = self:global('setmetatable')
  -- assigned to the name before `local self`, so that a class named self works
  E:w(format(
    '; %s = %s({__init = %s, __base = %s, __name = %q%s}, {__index = %s, __call = function(cls, ...) local self = %s({}, %s); cls.__init(self, ...); return self end}); %s.__class = %s',
    name, setmetatable, init, b, name, p and (', __parent = ' .. p) or '', index, setmetatable, b, b, name))
  if p then
    E:w(format('; %s(%s, %s.__base)', setmetatable, b, p))
  end
  E:w('; local self = ' .. name)
  if support then
    self.needs_class_support = true
    E:w('; ' .. (props and ('local ' .. props .. ' = ') or '') ..
      format('__hs_setup(self%s)', own and ', true' or ''))
  end

  local saved_cls = self.cls
  self.cls = { b = b, p = p }

  -- the lines of the properties, of their accessors (by 'get name' and 'set name'),
  -- and of the members sharing a name with one
  local properties, accessors, members = {}, {}, {}

  for _, item in ipairs(s.body) do
    if item.k == 'prop' then
      local kn = key_name(item.key)
      if kn then
        if properties[kn] then
          self:error(format("'%s' is already defined as a property on line %d of this class",
            kn, properties[kn]), item, #kn)
        end
        members[kn] = members[kn] or item.line
      end
      self:class_member(item.line, item.key, item.value)
    elseif item.k == 'meta' then
      for _, entry in ipairs(item.entries) do
        local name = meta_name(entry)
        -- the fallbacks get other names, as the base's own __index and __newindex
        -- dispatch
        if is_fallback(name) then name = '__hs_' .. string.sub(name, 3) end
        self:class_member(entry.line, name, entry.v)
      end
    elseif item.k == 'accessor' then
      local pname, kind, value = item.name, item.kind, item.value
      if members[pname] then
        self:error(format("'%s' is already defined on line %d of this class", pname,
          members[pname]), item.name_tok, #pname)
      end
      local given = kind .. ' ' .. pname
      if accessors[given] then
        self:error(format("'%s' is already given on line %d of this class", given,
          accessors[given]), item.name_tok, #pname)
      end
      accessors[given] = item.line
      local entry, first = props .. field(pname), not properties[pname]
      properties[pname] = properties[pname] or item.line
      E:stmt(item.line)
      if first then
        -- a new entry, which keeps the other accessor of an inherited property
        local other = kind == 'get' and 'set' or 'get'
        E:w(format('%s = {%s = %s and %s.%s, %s = ', entry, other, entry, entry, other, kind))
      else
        E:w(entry .. '.' .. kind .. ' = ')
      end
      self.cls.method, self.cls.accessor = pname, kind
      if value.k == 'Func' then
        -- like constructors, setters return nothing
        self:func(value, kind == 'set')
      else
        self:expr(value)
      end
      self.cls.method, self.cls.accessor = nil, nil
      if first then E:w('}') end
    elseif item.k == 'classvar' then
      E:stmt(item.line)
      E:w('self' .. field(item.key) .. ' = ')
      self.cls.method, self.cls.static = item.key, true
      self:expr(item.value)
      self.cls.method, self.cls.static = nil, nil
    else
      self:stmt(item)
      if item.k == 'Assign' then self:assigned(item.targets) end
    end
  end

  self.cls = saved_cls
  self:pop_scope()
  E:sp()
  E:w('end')
end

-- Expressions

function Compiler:expr(e, min)
  self.E:at(e.line)
  local handler = expr_handlers[e.k]
  if handler then
    return handler(self, e, min or 0)
  end
  if value_blocks[e.k] then
    return self:iife(e)
  end
  self:error('unexpected ' .. e.k, e)
end

function Compiler:expr_list(list)
  for i, e in ipairs(list) do
    if i > 1 then self.E:w(', ') end
    self:expr(e)
  end
end

-- An expression used as the receiver of a call, index or field access.
function Compiler:prefix(e)
  if prefix_kinds[e.k] then
    return self:expr(e)
  end
  self.E:at(e.line)
  self.E:w('(')
  self:expr(e)
  self.E:w(')')
end

function Compiler:e_Nil() self.E:w('nil') end
function Compiler:e_True() self.E:w('true') end
function Compiler:e_False() self.E:w('false') end
function Compiler:e_Number(e)
  if not self.target.ffi_numbers and match(e.v, '[lLiI]$') then
    self:error(format("'%s': 64-bit integer and imaginary numbers need LuaJIT", e.v), e, #e.v)
  end
  self.E:w(e.v)
end
function Compiler:e_Raw(e) self.E:w(e.code) end

function Compiler:e_Vararg(e)
  if not self.fn.vararg then
    self:error("'...' can only be used in a function taking '...'", e)
  end
  self.E:w('...')
end

function Compiler:e_Name(e)
  self:check_name(e.v, e)
  -- A name declared before its own value is still nil there, until the value is
  -- assigned, so only a function in the value can read it, when it's called later.
  -- The functions value blocks compile to run at once, so they don't count.
  local decl = self.scope:lookup(e.v)
  -- likewise a class body's local, declared up front, is nil until it's assigned
  local nil_in = decl and (decl.assigning or decl.unassigned)
  if nil_in then
    local fn = self.fn
    while fn ~= nil_in and fn.iife do fn = fn.parent end
    if fn == nil_in and decl.assigning then
      self:error(format(
        "'%s' is read in its own value, where it's the new local and still nil; assign it in a statement of its own, or rename",
        e.v), e, #e.v)
    elseif fn == nil_in then
      self:error(format(
        "'%s' is read before line %d assigns it, so it's still nil here; assign it first, as the class body runs in order",
        e.v, decl.assigned_on), e, #e.v)
    end
  end
  self.E:w(e.v)
end

function Compiler:e_Self(e)
  self:need_self(e)
  self.E:w('self')
end

function Compiler:e_SelfField(e)
  self:need_self(e)
  self.E:w('self' .. field(e.name))
end

function Compiler:e_ClassRef(e)
  self:need_self(e)
  self.E:w('self.__class')
end

function Compiler:e_ClassField(e)
  self:need_self(e)
  self.E:w('self.__class' .. field(e.name))
end

function Compiler:e_WithField(e)
  self.E:w(self:with_var(e) .. field(e.name))
end

function Compiler:e_WithCall(e)
  self:invoke(raw(self:with_var(e)), e.name, e.args)
end

function Compiler:e_Super(e)
  self.E:w(self:super_cls(e).p)
end

function Compiler:e_Field(e)
  self:prefix(e.obj)
  self.E:w(field(e.name))
end

function Compiler:e_Index(e)
  self:prefix(e.obj)
  self.E:w('[')
  self:expr(e.key)
  self.E:w(']')
end

function Compiler:e_Slice(e)
  self:error("slices can only be used in loops, as in 'for x in *t[2,]'", e)
end

function Compiler:e_Paren(e)
  self.E:w('(')
  self:expr(e.e)
  self.E:w(')')
end

function Compiler:args(args, first)
  local E = self.E
  E:w('(')
  if first then
    E:w(first)
    if #args > 0 then E:w(', ') end
  end
  self:expr_list(args)
  E:w(')')
end

-- obj:name(args), also when name is a Lua keyword.
function Compiler:invoke(obj, name, args)
  local E = self.E
  if valid_name(name) then
    self:prefix(obj)
    E:w(':' .. name)
    self:args(args)
  elseif obj.k == 'Name' or obj.k == 'Self' or (obj.k == 'Raw' and match(obj.code, '^[%a_][%w_]*$')) then
    self:expr(obj)
    E:w(field(name))
    E:w('(')
    self:expr(obj)
    if #args > 0 then E:w(', ') end
    self:expr_list(args)
    E:w(')')
  else
    -- the receiver can't be evaluated twice
    self.needs_invoke = true
    E:w('__hs_invoke(')
    self:expr(obj)
    E:w(', ' .. format('%q', name))
    if #args > 0 then E:w(', ') end
    self:expr_list(args)
    E:w(')')
  end
end

function Compiler:e_Call(e)
  local fn = e.fn
  local E = self.E
  if fn.k == 'SelfField' then
    -- @m(...) is a method call on self
    self:need_self(fn)
    self:invoke(raw('self'), fn.name, e.args)
  elseif fn.k == 'ClassField' then
    self:need_self(fn)
    self:invoke(raw('self.__class'), fn.name, e.args)
  elseif fn.k == 'Super' then
    -- the parent's version of the current method: a method of its base, or with
    -- `@name:` a function of the parent class itself
    local cls = self:super_cls(fn, true)
    local method = cls.method
    self:need_self(fn)
    if cls.accessor then
      -- in an accessor, the parent's accessor of the same kind
      E:w(cls.p .. '.__base.__properties' .. field(method) .. '.' .. cls.accessor)
    elseif method == 'new' and not cls.static then
      E:w(cls.p .. '.__init')
    else
      E:w(cls.p .. (cls.static and '' or '.__base'))
      if type(method) == 'string' then
        E:w(field(method))
      else
        -- a key given as an expression is evaluated again
        E:w('[')
        self:expr(method)
        E:w(']')
      end
    end
    self:args(e.args, 'self')
  else
    self:prefix(fn)
    self:args(e.args)
  end
end

function Compiler:e_MethodCall(e)
  if e.obj.k == 'Super' then
    local cls = self:super_cls(e.obj)
    self:need_self(e.obj)
    self.E:w(cls.p .. field(e.name))
    return self:args(e.args, 'self')
  end
  self:invoke(e.obj, e.name, e.args)
end

-- How the target compiles the bitwise operator of `e` (see targets.lua), an error
-- where it has none.
function Compiler:bitwise(e)
  local how = self.target.bitwise
  if not how then
    local t = e.op_tok or e
    local op = e.op_tok and e.op_tok.v or e.op
    self:error(format("'%s': portable Lua has no bitwise operators; compile for a target", op), t, #op)
  end
  return how
end

-- Compiles `e` as a single value where it's an argument, which would otherwise pass
-- on all the values of a call or '...'.
function Compiler:single(e)
  if calls[e.k] or e.k == 'Vararg' then
    self.E:w('(')
    self:expr(e)
    return self.E:w(')')
  end
  self:expr(e)
end

-- Calls the function `name` of the target's bit library with `operands`, which is
-- what a bitwise operator compiles to on a Lua without them. The function is
-- localized once at the top (see compile()), as hand-tuned Lua would.
function Compiler:bit_call(name, operands)
  local E = self.E
  self.bit_helpers[name] = true
  E:w('__hs_' .. name .. '(')
  for i, operand in ipairs(operands) do
    if i > 1 then E:w(', ') end
    self:single(operand)
  end
  E:w(')')
end

function Compiler:e_Unop(e, min)
  local E = self.E
  if e.op == '~' and self:bitwise(e) ~= 'operators' then
    return self:bit_call('bnot', { e.e })
  end
  local paren = UNARY < min
  if paren then E:w('(') end
  if e.op == 'not' then
    E:w('not ')
  elseif e.op == '-' and e.e.k == 'Unop' and e.e.op == '-' then
    E:w('- ') -- '--' would start a comment
  else
    E:w(e.op)
  end
  self:expr(e.e, UNARY)
  if paren then E:w(')') end
end

function Compiler:e_Binop(e, min)
  local E = self.E
  local op = e.op == '!=' and '~=' or e.op

  if bit_functions[op] and self:bitwise(e) ~= 'operators' then
    -- a chain of the same operator is a single call: `a | b | c` as bor(a, b, c)
    local chain, l = { e.r }, e.l
    while nary_bit_ops[op] and l.k == 'Binop' and l.op == op do
      chain[#chain + 1] = l.r
      l = l.l
    end
    chain[#chain + 1] = l
    local operands = {}
    for i = #chain, 1, -1 do operands[#operands + 1] = chain[i] end
    return self:bit_call(bit_functions[op], operands)
  elseif op == '//' and not self.target.floor_division then
    self.needs_floor = true
    E:w('__hs_floor(')
    self:expr({ k = 'Binop', op = '/', l = e.l, r = e.r })
    return E:w(')')
  end

  local p = precedence[op]
  local paren = p < min
  if paren then E:w('(') end
  local lmin, rmin = p, p + 1
  if op == '..' or op == '^' then
    lmin, rmin = p + 1, p
  end
  self:expr(e.l, lmin)
  E:w(' ' .. op .. ' ')
  self:expr(e.r, rmin)
  if paren then E:w(')') end
end

-- The names type() gives, which a string on the right of is_a must be one of.
-- cdata is LuaJIT's, accepted for every target so code can check for it anywhere.
local type_names = {
  ['nil'] = true, boolean = true, number = true, string = true, table = true,
  ['function'] = true, thread = true, userdata = true, cdata = true,
}

-- `obj is_a cls` walks the instance's class and its parents; see the
-- __hs_is_a helper prepended in compile() for what it compiles to.
function Compiler:e_IsA(e)
  local E = self.E
  local cls = e.cls
  -- a literal type name can be checked now; one with escapes is left alone
  if cls.k == 'String' and #cls.parts == 1 and type(cls.parts[1]) == 'string'
      and not find(cls.parts[1], '\\', 1, true) and not type_names[cls.parts[1]] then
    self:error(format(
      "'%s' isn't a Lua type name; type() gives nil, boolean, number, string, table, function, thread, userdata or cdata",
      cls.parts[1]), cls, #cls.parts[1] + 2)
  end
  self.needs_is_a = true
  E:w('__hs_is_a(')
  self:expr(e.obj)
  E:w(', ')
  self:expr(e.cls)
  E:w(')')
end

function Compiler:e_String(e, min)
  local E = self.E
  local parts, q = e.parts, e.q
  if q == '[' then return E:w(parts[1]) end
  if #parts == 0 then return E:w(q .. q) end
  if #parts == 1 and type(parts[1]) == 'string' then
    return E:w(q .. parts[1] .. q)
  end

  local paren = #parts > 1 and precedence['..'] < min
  if paren then E:w('(') end
  for i, part in ipairs(parts) do
    if i > 1 then E:w(' .. ') end
    if type(part) == 'string' then
      E:w(q .. part .. q)
    else
      E:w(self:global('tostring') .. '(')
      self:expr(part)
      E:w(')')
    end
  end
  if paren then E:w(')') end
end

function Compiler:e_Table(e)
  local E = self.E
  E:w('{')
  for i, entry in ipairs(e.entries) do
    if i > 1 then E:w(', ') end
    E:at(entry.line)
    if entry.k == 'pos' then
      self:expr(entry.v)
    elseif entry.k == 'named' then
      E:w(key(entry.key) .. ' = ')
      self:expr(entry.v)
    else
      E:w('[')
      self:expr(entry.key)
      E:w('] = ')
      self:expr(entry.v)
    end
  end
  E:w('}')
end

function Compiler:e_Func(e)
  self:func(e)
end

-- Emits a function. Defaults are applied in the order the parameters are written.
function Compiler:func(e, no_return)
  local E = self.E
  local names = {}
  local vararg = false
  if e.fat then names[1] = 'self' end
  for _, p in ipairs(e.params) do
    if p.vararg then
      vararg = true
      names[#names + 1] = '...'
    else
      names[#names + 1] = p.name
    end
  end

  E:w('function(' .. concat(names, ', ') .. ')')
  local saved_fn = self.fn
  self.fn = { vararg = vararg }
  self:push_scope()
  if e.fat then self.scope:declare('self', e.line) end
  for _, p in ipairs(e.params) do
    if p.name then self:bind(p.name, p.tok, 'parameter') end
  end

  for _, p in ipairs(e.params) do
    if p.default then
      E:stmt()
      E:w('if ' .. p.name .. ' == nil then ' .. p.name .. ' = ')
      self:expr(p.default)
      E:w(' end')
    end
  end

  self:block(e.body, not no_return and IMPLICIT_RETURN or nil)
  self:pop_scope()
  self.fn = saved_fn
  E:sp()
  E:w('end')
end

for name, method in pairs(Compiler) do
  local kind = match(name, '^stmt_(%u%w*)$')
  if kind then stmt_handlers[kind] = method end
  kind = match(name, '^e_(%u%w*)$')
  if kind then expr_handlers[kind] = method end
end

-- Compiles for the Lua `target` describes (see targets.lua), by default the running
-- one.
local function compile(stmts, source, target)
  local c = new(source, target or runtime)
  c.fn = { vararg = true }
  c.scope = Scope.new(nil)
  c.scope.fn = c.fn
  c:block(stmts, IMPLICIT_RETURN)
  local lua = c.E:result()
  local body = lua
  local helpers = {}
  for name in pairs(c.bit_helpers) do helpers[#helpers + 1] = name end
  if #helpers > 0 then
    table.sort(helpers)
    local locals, values = {}, {}
    for i, name in ipairs(helpers) do
      locals[i] = '__hs_' .. name
      values[i] = format("require('%s').%s", c.target.bitwise, name)
    end
    lua = format('local %s = %s ', concat(locals, ', '), concat(values, ', ')) .. lua
  end
  if c.needs_floor then
    lua = 'local __hs_floor = math.floor ' .. lua
  end
  local globals = {}
  for name in pairs(c.globals) do globals[#globals + 1] = name end
  if #globals > 0 then
    table.sort(globals)
    local locals = {}
    for i, name in ipairs(globals) do locals[i] = '__hs_' .. name end
    lua = format('local %s = %s ', concat(locals, ', '), concat(globals, ', ')) .. lua
  end
  if c.needs_is_a then
    -- a string names a Lua type, `x is_a 'string'`; otherwise an instance's class
    -- is on its base, and we walk it and the parents up to cls. Anything else on
    -- the right, like the nil of a misspelt class, is an error rather than false.
    lua = "local function __hs_is_a(o, c) " ..
      "local tc = type(c) " ..
      "if tc == 'string' then return type(o) == c end " ..
      "if tc ~= 'table' then error('is_a needs a class or a type name on the right, got ' .. tc, 2) end " ..
      "local p = type(o) == 'table' and o.__class " ..
      "while p do if p == c then return true end p = p.__parent end " ..
      "return false end " .. lua
  end
  if c.needs_invoke then
    lua = 'local function __hs_invoke(o, k, ...) return o[k](o, ...) end ' .. lua
  end
  if c.needs_class_support then
    lua = CLASS_SUPPORT .. lua
  end
  if c.E.leading_paren and #lua > #body then
    -- the first statement starts with '(', which would continue the helpers' last
    -- statement as a call
    lua = string.sub(lua, 1, #lua - #body) .. ';' .. body
  end
  return lua
end

return {
  compile = compile,
}
