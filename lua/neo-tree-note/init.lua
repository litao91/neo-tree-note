--This file should have all functions that are in the public api and either set
--or read the state of this source.

local vim = vim
local renderer = require("neo-tree.ui.renderer")
local manager = require("neo-tree.sources.manager")
local events = require("neo-tree.events")
local log = require("neo-tree.log")
local utils = require("neo-tree.utils")
local mainlibdb = require("neo-tree-note.lib.mainlibdb")
local luv = vim.loop
local vfs_scan = require("neo-tree-note.lib.vfs_scan")

local M = { name = "neo-tree-note" }

---Navigate to the given path.
---@param uuid string **id** to navigate to. If empty, will navigate to the root.
M.navigate = function(state, uuid, uuid_to_reveal, callback, async)
	log.trace("navigate", state, uuid, uuid_to_reveal, async)
	utils.debounce("mdtree_navigate", function()
		M._navigate_internal(state, uuid, uuid_to_reveal, callback, async)
	end, utils.debounce_strategy.CALL_FIRST_AND_LAST, 100)
end

M._navigate_internal = function(state, uuid, uuid_to_reveal, callback, async)
	if uuid ~= nil and uuid ~= "0" then
		log.error("Unsupported, could start from the root only")
		return
	end
	log.trace("navigate_internal", state.current_position, uuid, uuid_to_reveal)
	state.uuid_path = "0"
	state.name = "/"
	if uuid_to_reveal then
		renderer.position.set(state, uuid_to_reveal)
	end
	vfs_scan.get_items(state, nil, nil, uuid_to_reveal, callback)
end

M.toggle_category = function(state, node, path_to_reveal, skip_redraw, recursive)
	log.debug("toggle_directory", state, node, path_to_reveal, skip_redraw, recursive)
	local tree = state.tree
	if not node then
		node = tree:get_node()
	end
	if node.type ~= "directory" then
		return
	end
	state.explicitly_opened_directories = state.explicitly_opened_directories or {}
	if node.loaded == false then
		local id = node:get_id()
		state.explicitly_opened_directories[id] = true
		renderer.position.set(state, nil)
		vfs_scan.get_items(state, id, node.name, path_to_reveal, nil, false, recursive)
	elseif node:has_children() then
		local updated = false
		if node:is_expanded() then
			updated = node:collapse()
			state.explicitly_opened_directories[node:get_id()] = false
		else
			updated = node:expand()
			state.explicitly_opened_directories[node:get_id()] = true
		end
		if updated and not skip_redraw then
			renderer.redraw(state)
		end
		if path_to_reveal then
			renderer.focus_node(state, path_to_reveal)
		end
	end
end

---Configures the plugin, should be called before the plugin is used.
---@param config table Configuration table containing any keys that the user
--wants to change from the defaults. May be empty to accept default values.
M.setup = function(config, global_config)
	local working_dir = config.working_dir or luv.working_dir
	if not mainlibdb.init({ working_dir = working_dir }) then
		log.error("Fail to init mainlibdb with working dir: " .. working_dir)
	end
end

return M
