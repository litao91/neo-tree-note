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

local get_state = function(tabnr)
	return manager.get_state(M.name, tabnr)
end
function string:endswith(ending)
	return ending == "" or self:sub(-#ending) == ending
end

local test_is_in_path = function(lhs, rhs)
	if lhs == "0" then
		return false
	end
	local uuid_path = mainlibdb.find_virtual_uuid_path(lhs)
	for _, value in ipairs(uuid_path) do
		if value == rhs then
			return true
		end
	end
	return false
end

local follow_internal = function(callback, force_show, async)
	if vim.bo.filetype == "neo-tree" or vim.bo.filetype == "neo-tree-popup" then
		return
	end
	local path_to_reveal = manager.get_path_to_reveal()
	if not utils.truthy(path_to_reveal) then
		return false
	end

	if not path_to_reveal:endswith(".md") then
		return false
	end
	local _, uuid_to_reveal = utils.split_path(path_to_reveal)
	uuid_to_reveal = string.sub(uuid_to_reveal, 1, #uuid_to_reveal - #".md")

	local state = get_state()
	if state.current_position == "float" then
		return false
	end

	if not state.uuid_path then
		return false
	end

	local window_exists = renderer.window_exists(state)
	if window_exists then
		local node = state.tree and state.tree:get_node()
		if node then
			if node:get_id() == path_to_reveal then
				-- already focused
				return false
			end
		end
	else
		if not force_show then
			return false
		end
	end

	log.debug("following uuid: " .. uuid_to_reveal)
	local show_only_explicitly_opened = function()
		local eod = state.explicitly_opened_directories or {}
		local expanded_nodes = renderer.get_expanded_nodes(state.tree)
		local state_changed = false
		for _, id in ipairs(expanded_nodes) do
			local is_explicit = eod[id]
			if not is_explicit then
				local is_in_path = test_is_in_path(id, uuid_to_reveal)
				if is_in_path then
					is_explicit = true
				end
			end
			if not is_explicit then
				local node = state.tree:get_node(id)
				if node then
					node:collapse()
					state_changed = true
				end
			end
			if state_changed then
				renderer.redraw(state)
			end
		end
	end
	state.position.is.restorable = false -- we will handle setting cursor position here
	vfs_scan.get_items(state, nil, nil, uuid_to_reveal, function()
		show_only_explicitly_opened()
		renderer.focus_node(state, uuid_to_reveal, true)
		if type(callback) == "function" then
			callback()
		end
	end, async)
	return true
end

M.follow = function()
	if vim.fn.bufname(0) == "COMMIT_EDITMSG" then
		return false
	end
	utils.debounce("neo-tree-buffer-follow", function()
		return follow_internal()
	end, 100, utils.debounce_strategy.CALL_LAST_ONLY)
end
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
	state.dirty = false
	local is_search = utils.truthy(state.search_pattern)
	log.trace("navigate_internal", state.current_position, uuid, uuid_to_reveal)
	state.uuid = "0"
	state.name = "/"

	if uuid_to_reveal then
		renderer.position.set(state, uuid_to_reveal)
		log.debug(
			"navigate_internal: in path_to_reveal, state.position is ",
			state.position.node_id,
			", restorable = ",
			state.position.is.restorable
		)
		vfs_scan.get_items(state, nil, nil, uuid_to_reveal, callback)
	else
		local is_current = state.current_position == "current"
		local follow_file = state.follow_current_file
			and not is_search
			and not is_current
			and manager.get_path_to_reveal()
		local handled = false
		if utils.truthy(follow_file) then
			handled = follow_internal(callback, true, async)
		end
		if not handled then
			local success, msg = pcall(renderer.position.save, state)
			if success then
				log.trace("navigate_internal: position saved")
			else
				log.trace("navigate_internal: FAILED to save position: ", msg)
			end
			vfs_scan.get_items(state, nil, nil, nil, callback)
		end
	end
end

M.toggle_category = function(state, node, uuid_to_reveal, skip_redraw, recursive)
	log.debug("toggle_directory", state, node, uuid_to_reveal, skip_redraw, recursive)
	local tree = state.tree
	if not node then
		node = tree:get_node()
	end
	if node.type ~= "directory" then
		return
	end
	state.explicitly_opened_directories = state.explicitly_opened_directories or {}
	if not node.loaded then
		local id = node:get_id()
		state.explicitly_opened_directories[id] = true
		renderer.position.set(state, nil)
		vfs_scan.get_items(state, id, node.name, uuid_to_reveal, nil, false, recursive)
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
		if uuid_to_reveal then
			renderer.focus_node(state, uuid_to_reveal)
		end
	end
end

---Configures the plugin, should be called before the plugin is used.
---@param config table Configuration table containing any keys that the user
--wants to change from the defaults. May be empty to accept default values.
M.setup = function(config, global_config)
	config.working_dir = config.working_dir or luv.cwd()
	if not mainlibdb.init({ working_dir = config.working_dir }) then
		return
	end

	-- Configure event handler for follow_current_file option
	if config.follow_current_file then
		manager.subscribe(M.name, {
			event = events.VIM_BUFFER_ENTER,
			handler = M.follow,
		})
		manager.subscribe(M.name, {
			event = events.VIM_TERMINAL_ENTER,
			handler = M.follow,
		})
	end
end

return M
