--This file should have all functions that are in the public api and either set
--or read the state of this source.

local vim = vim
local renderer = require("neo-tree.ui.renderer")
local manager = require("neo-tree.sources.manager")
local events = require("neo-tree.events")
local log = require("neo-tree.log")
local utils = require("neo-tree.utils")
local mainlibdb = require('neo-tree-note.lib.mainlibdb')
local luv = vim.loop

local M = { name = "neo-tree-note" }

---Navigate to the given path.
---@param path string Path to navigate to. If empty, will navigate to the cwd.
M.navigate = function(state, path, path_to_reveal, callback, async)
	log.trace("navigate", state, path, path_to_reveal, async)
	utils.debounce("mdtree_navigate", function()
		M._navigate_internal(state, path, path_to_reveal, callback, async)
	end, utils.debounce_strategy.CALL_FIRST_AND_LAST, 100)
end

M._navigate_internal = function(state, path, path_to_reveal, callback, async)
	log.trace("navigate_internal", state.current_position, path, path_to_reveal)
	state.dirty = false
	local is_search = utils.truthy(state.search_pattern)
	local items = {
		{
			id = "1",
			name = "root",
			type = "directory",
			children = {
				{
					id = "1.1",
					name = "child1",
					type = "directory",
					children = {
						{
							id = "1.1.1",
							name = "child1.1 (you'll need a custom renderer to display this properly)",
							type = "custom",
							extra = { custom_text = "HI!" },
						},
						{
							id = "1.1.2",
							name = "child1.2",
							type = "file",
						},
					},
				},
			},
		},
	}
	renderer.show_nodes(items, state)
end

---Configures the plugin, should be called before the plugin is used.
---@param config table Configuration table containing any keys that the user
--wants to change from the defaults. May be empty to accept default values.
M.setup = function(config, global_config)
	local working_dir = config.working_dir or luv.working_dir
	if not mainlibdb.init({working_dir = working_dir}) then
		log.error("Fail to init mainlibdb with working dir: " .. working_dir)
	end
end

return M
