// Copyright 2026 Nils Nordman
// License: MIT (see LICENSE.md at the top-level directory of the distribution)
//
// Checks the extension with VS Code's own TextMate engine: that the grammars load,
// that every Howlscript file and doc example in the repo leaves no string or block
// open, that some tokens get the scopes themes color, and that the language
// configuration's indentation rules match the lines they should.

'use strict';

const fs = require('fs');
const path = require('path');
const vsctm = require('vscode-textmate');
const oniguruma = require('vscode-oniguruma');

const EXT = path.join(__dirname, '..');
const ROOT = path.join(EXT, '..', '..');

let failures = 0;
function fail(message) {
  failures++;
  console.error('FAIL: ' + message);
}

function files(dir, suffix) {
  const found = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, entry.name);
    if (entry.isDirectory()) found.push(...files(p, suffix));
    else if (entry.name.endsWith(suffix)) found.push(p);
  }
  return found.sort();
}

// The ```howl blocks of a Markdown file, with the line each starts on
function howlBlocks(file) {
  const blocks = [];
  let block = null;
  fs.readFileSync(file, 'utf8').split('\n').forEach((line, i) => {
    if (block) {
      if (/^\s*```\s*$/.test(line)) {
        blocks.push(block);
        block = null;
      } else {
        block.lines.push(line);
      }
    } else if (/^\s*```howl\b/.test(line)) {
      block = { line: i + 2, lines: [] };
    }
  });
  return blocks;
}

async function loadRegistry() {
  const wasm = fs.readFileSync(require.resolve('vscode-oniguruma/release/onig.wasm'));
  await oniguruma.loadWASM(wasm.buffer.slice(wasm.byteOffset, wasm.byteOffset + wasm.byteLength));
  const grammars = {
    'source.howl': 'howl.tmLanguage.json',
    'markdown.howl.codeblock': 'howl-markdown.tmLanguage.json',
  };
  return new vsctm.Registry({
    onigLib: Promise.resolve({
      createOnigScanner: (patterns) => new oniguruma.OnigScanner(patterns),
      createOnigString: (s) => new oniguruma.OnigString(s),
    }),
    loadGrammar: async (scopeName) => {
      const file = grammars[scopeName];
      if (!file) return null;
      const p = path.join(EXT, 'syntaxes', file);
      return vsctm.parseRawGrammar(fs.readFileSync(p, 'utf8'), p);
    },
  });
}

// Tokenizes lines, returning each line's tokens with their text and the state after
function tokenize(grammar, lines, state = vsctm.INITIAL) {
  const result = [];
  for (const line of lines) {
    const r = grammar.tokenizeLine(line, state);
    result.push(r.tokens.map((t) => ({ text: line.slice(t.startIndex, t.endIndex), scopes: t.scopes })));
    state = r.ruleStack;
  }
  return { lines: result, state };
}

// A lone `nil` after the lines gets only its own scopes when nothing is left open
function leavesOpen(grammar, lines) {
  const { state } = tokenize(grammar, lines);
  const [tokens] = tokenize(grammar, ['nil'], state).lines;
  const scopes = tokens[0].scopes.join(' ');
  return scopes === 'source.howl constant.language.nil.howl' ? null : scopes;
}

function checkCorpus(grammar) {
  let count = 0;
  for (const file of files(path.join(ROOT, 'spec'), '.howl')) {
    count++;
    const open = leavesOpen(grammar, fs.readFileSync(file, 'utf8').split('\n'));
    if (open) fail(`${path.relative(ROOT, file)} leaves open: ${open}`);
  }
  const docs = ['REFERENCE.md', 'CONVERTING.md', 'README.md'].map((f) => path.join(ROOT, f));
  docs.push(...files(path.join(ROOT, 'site', 'manual'), '.md'));
  docs.push(...files(path.join(ROOT, 'site', 'content'), '.md'));
  for (const file of docs) {
    if (!fs.existsSync(file)) continue;
    for (const block of howlBlocks(file)) {
      count++;
      const open = leavesOpen(grammar, block.lines);
      if (open) fail(`${path.relative(ROOT, file)}:${block.line}: the example leaves open: ${open}`);
    }
  }
  console.log(`${count} files and examples tokenized`);
}

// [line, a token's text, a scope one of its scopes must start with]
const SCOPES = [
  ['x = 1 -- a note', ' a note', 'comment.line.double-dash'],
  ['x--', '--', 'keyword.operator.increment'],
  ["s = 'text'", 'text', 'string.quoted.single'],
  ['s = "a #{b} c"', 'a ', 'string.quoted.double'],
  ['s = "a #{b} c"', 'b', 'source.howl'],
  ['s = [[long]]', 'long', 'string.quoted.other.multiline'],
  ['if x then y', 'if', 'keyword.control'],
  ['unless done', 'unless', 'keyword.control'],
  ['class A extends B', 'A', 'entity.name.type.class'],
  ['f = (a, b) -> a', 'f', 'entity.name.function'],
  ['  new: (x) =>', 'new', 'entity.name.function'],
  ['  get size: => #@items', 'size', 'entity.name.function'],
  ['line = get_line()', 'get_line', 'meta.function-call'],
  ["describe 'x', ->", 'describe', 'meta.function-call'],
  ['obj:show(1)', 'show', 'meta.function-call'],
  ['t.insert(x)', 'insert', 'meta.function-call'],
  ['@reset(1)', 'reset', 'meta.function-call'],
  ['p = Point {x: 1}', 'Point', 'meta.function-call'],
  ['f = (a, b) -> a', 'b', 'variable.parameter'],
  ['f = (a, b) -> a', '->', 'storage.type.function'],
  ['@name = 1', '@name', 'variable.language.self'],
  ['ok = a is_a B', 'is_a', 'keyword.operator.type'],
  ['x <<= 2', '<<=', 'keyword.operator.assignment.compound'],
  ['x ^= 2', '^=', 'keyword.operator.assignment.compound'],
  ['#!/usr/bin/env howlscript', '#!/usr/bin/env howlscript', 'comment.line.shebang'],
  ['max <const> = 10', 'const', 'storage.modifier'],
  ['lock <close> = Lock()', 'close', 'storage.modifier'],
  ['n = 0xff', '0xff', 'constant.numeric'],
  ['  goto done if found', 'goto', 'keyword.control'],
  ['  goto done if found', 'done', 'entity.name.label'],
  ['::done::', 'done', 'entity.name.label'],
];

function checkScopes(grammar) {
  for (const [line, text, scope] of SCOPES) {
    const [tokens] = tokenize(grammar, [line]).lines;
    const token = tokens.find((t) => t.text === text);
    if (!token) {
      fail(`'${line}': no token '${text}' in ${JSON.stringify(tokens.map((t) => t.text))}`);
    } else if (!token.scopes.some((s) => s.startsWith(scope))) {
      fail(`'${line}': '${text}' is ${token.scopes.join(' ')}, not ${scope}`);
    } else if (scope === 'meta.function-call' && token.scopes.length > 2) {
      // Calls look like other names, so that only definitions stand out
      fail(`'${line}': the call '${text}' is ${token.scopes.join(' ')}`);
    }
  }
}

function checkMarkdown(grammar) {
  const { lines } = tokenize(grammar, ['```howl', 'x = nil', '```', 'nil']);
  const nil = lines[1].find((t) => t.text === 'nil');
  if (!nil || !nil.scopes.includes('meta.embedded.block.howlscript') ||
      !nil.scopes.includes('constant.language.nil.howl')) {
    fail(`a howl block's nil isn't highlighted: ${JSON.stringify(lines[1])}`);
  }
  if (lines[3].some((t) => t.scopes.includes('meta.embedded.block.howlscript'))) {
    fail('the howl block goes on past its closing fence');
  }
}

const INDENT = {
  increase: [
    'if x > 0',
    'if x -- a note',
    '  elseif x == 0',
    'else',
    'else -- a note',
    'unless done',
    'while busy()',
    'for i = 1, 10',
    'for k, v in pairs(t)',
    'with Window()',
    'switch value',
    '  when 3',
    'class Point extends Base',
    'do',
    'f = (a) ->',
    '  new: (x) =>',
    'events.connect(\'saved\', (args) ->',
    't = {',
    'f(',
    'list = [',
    'f = -> -- a note',
  ],
  same: [
    'x = 1',
    'if c then a else b',
    'for x in *t do f(x)',
    'while c do f()',
    '  when 1 then a',
    'print(x) for x in *t',
    'return x if c',
    'f = -> x + 1',
    '-- if this, a comment',
    'elsewhere = 1',
    'format = 1',
  ],
  decrease: ['}', '  )', ']', 'else', '  elseif x', 'else print(x)'],
  outdent: ['  return x', 'break', '    continue', 'return'],
  noOutdent: ['return x if c', 'break unless done', 'return ->', 'return {', 'returned = 1'],
};

function checkIndentation() {
  const config = JSON.parse(fs.readFileSync(path.join(EXT, 'language-configuration.json'), 'utf8'));
  const increase = new RegExp(config.indentationRules.increaseIndentPattern);
  const decrease = new RegExp(config.indentationRules.decreaseIndentPattern);
  const outdent = new RegExp(config.onEnterRules[0].beforeText);
  for (const line of INDENT.increase) {
    if (!increase.test(line)) fail(`'${line}' doesn't indent the next line`);
  }
  for (const line of INDENT.same) {
    if (increase.test(line)) fail(`'${line}' indents the next line`);
    if (decrease.test(line)) fail(`'${line}' is outdented`);
  }
  for (const line of INDENT.decrease) {
    if (!decrease.test(line)) fail(`'${line}' isn't outdented`);
  }
  for (const line of INDENT.outdent) {
    if (!outdent.test(line)) fail(`'${line}' doesn't outdent the next line`);
  }
  for (const line of INDENT.noOutdent) {
    if (outdent.test(line)) fail(`'${line}' outdents the next line`);
  }
}

async function main() {
  const registry = await loadRegistry();
  const howl = await registry.loadGrammar('source.howl');
  const markdown = await registry.loadGrammar('markdown.howl.codeblock');
  checkCorpus(howl);
  checkScopes(howl);
  checkMarkdown(markdown);
  checkIndentation();
  if (failures > 0) {
    console.error(`${failures} failed`);
    process.exit(1);
  }
  console.log('all passed');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
