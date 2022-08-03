--This file should contain all commands meant to be used by mappings.
local cc = require("neo-tree.sources.common.commands")
local utils = require('neo-tree.utils')
local note = require('neo-tree-note')

local vim = vim

local M = {}

M.example_command = function(state)
  local tree = state.tree
  local node = tree:get_node()
  local id = node:get_id()
  local name = node.name
  print(string.format("example_command: id=%s, name=%s", id, name))
end

M.show_debug_info = function(state)
  print(vim.inspect(state))
end

M.toggle_node = function(state)
  cc.toggle_node(state, utils.wrap(note.toggle_category, state))
end

cc._add_common_commands(M)
return M
