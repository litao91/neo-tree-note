--This file should contain all commands meant to be used by mappings.
local cc = require("neo-tree.sources.common.commands")
local utils = require("neo-tree.utils")
local note = require("neo-tree-note")
local renderer = require("neo-tree.ui.renderer")
local note_utils = require("neo-tree-note.lib.utils")

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

local open_article = function(state, uuid_path, cmd, open_file)
	local real_path = note_utils.get_article_file_path(state, uuid_path)
	if type(open_file) == "function" then
		open_file(state, real_path, cmd)
	else
		utils.open_file(state, real_path, cmd)
	end
end

---Open file or directory
---@param state table The state of the source
---@param open_cmd string The vim command to use to open the file
---@param toggle_directory function The function to call to toggle a directory
---open/closed
local open_with_cmd = function(state, open_cmd, toggle_directory, open_file)
	local tree = state.tree
	local success, node = pcall(tree.get_node, tree)
	if node.type == "message" then
		return
	end
	if not (success and node) then
		log.debug("Could not get node.")
		return
	end

	local function open()
		local path = node:get_id()
		if type(open_file) == "function" then
			open_file(state, path, open_cmd)
		else
			utils.open_file(state, path, open_cmd)
		end
	end

	if utils.is_expandable(node) then
		if toggle_directory and node.type == "directory" then
			toggle_directory(node)
		elseif node:has_children() then
			if node:is_expanded() and node.type == "file" then
				return open()
			end

			local updated = false
			if node:is_expanded() then
				updated = node:collapse()
			else
				updated = node:expand()
			end
			if updated then
				renderer.redraw(state)
			end
		end
	else
		open()
	end
end

---Marks potential windows with letters and will open the give node in the picked window.
---@param state table The state of the source
---@param path string The path to open
---@param cmd string Command that is used to perform action on picked window
local use_window_picker = function(state, path, cmd)
	local success, picker = pcall(require, "window-picker")
	if not success then
		print("You'll need to install window-picker to use this command: https://github.com/s1n7ax/nvim-window-picker")
		return
	end
	local events = require("neo-tree.events")
	local event_result = events.fire_event(events.FILE_OPEN_REQUESTED, {
		state = state,
		path = path,
		open_cmd = cmd,
	}) or {}
	if event_result.handled then
		events.fire_event(events.FILE_OPENED, path)
		return
	end
	local picked_window_id = picker.pick_window()
	if picked_window_id then
		vim.api.nvim_set_current_win(picked_window_id)
		vim.cmd(cmd .. " " .. vim.fn.fnameescape(path))
	end
	events.fire_event(events.FILE_OPENED, path)
end

M.open = function(state)
	open_with_cmd(state, "edit", utils.wrap(M.toggle_node, state), open_article)
end
M.open_split = function(state)
	open_with_cmd(state, "split", utils.wrap(M.toggle_node, state), open_article)
end
M.open_vsplit = function(state)
	open_with_cmd(state, "vsplit", utils.wrap(M.toggle_node, state), open_article)
end
M.open_tabnew = function(state)
	open_with_cmd(state, "tabnew", utils.wrap(M.toggle_node, state), open_article)
end

---Marks potential windows with letters and will open the give node in the picked window.
M.open_with_window_picker = function(state)
	open_with_cmd(state, "edit", utils.wrap(M.toggle_node, state), function(state, uuid_path, cmd)
		open_article(state, uuid_path, cmd, use_window_picker)
	end)
end

---Marks potential windows with letters and will open the give node in a split next to the picked window.
M.split_with_window_picker = function(state)
	open_with_cmd(state, "split", utils.wrap(M.toggle_node, state), function(state, uuid_path, cmd)
		open_article(state, uuid_path, cmd, use_window_picker)
	end)
end

---Marks potential windows with letters and will open the give node in a vertical split next to the picked window.
M.vsplit_with_window_picker = function(state)
	open_with_cmd(state, "vsplit", utils.wrap(M.toggle_node, state), function(state, uuid_path, cmd)
		open_article(state, uuid_path, cmd, use_window_picker)
	end)
end

cc._add_common_commands(M)
return M
