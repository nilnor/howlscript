+++
title = "Editor support"
description = "Highlighting and other help for Howlscript in your editor."
weight = 90

[extra]
placeholder = true
+++

This chapter will list editor plugins for Howlscript as they become available, and
how to set them up. Until then, an editor's MoonScript highlighting comes close for
`.howl` files.

Tools that check Howlscript as you type can use `howlscript compile`, which exits
with 1 and prints `file:line:col: message` when a file doesn't compile, or the Lua
module's `to_lua`, which returns the error's position as a table (see
[Using it from Lua](@/manual/from-lua.md#compiling-to-lua)).
