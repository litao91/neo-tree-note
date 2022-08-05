--This file should contain all commands meant to be used by mappings.
local cc = require("neo-tree.sources.common.commands")
local utils = require("neo-tree.utils")
local note = require("neo-tree-note")
local events = require("neo-tree.events")
local renderer = require("neo-tree.ui.renderer")
local note_utils = require("neo-tree-note.lib.utils")
local mainlibdb = require("neo-tree-note.lib.mainlibdb")
local inputs = require("neo-tree.ui.inputs")
local luv = vim.loop

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

---Gets the node parent folder recursively
---@param tree table to look for nodes
---@param node table to look for folder parent
---@return table table
local function get_folder_node(tree, node)
	if not node then
		node = tree:get_node()
	end
	if node.type == "directory" then
		return node
	end
	return get_folder_node(tree, tree:get_node(node:get_parent_id()))
end

local function create_article(working_dir, cat_uuid, name)
	local uuid = mainlibdb.add_article(cat_uuid)
	local file = utils.path_join(working_dir, "docs", uuid .. ".md")

	if luv.fs_access(file, "r") ~= false then
		print(file .. " already exists. Overwrite? y/n")
		local ans = utils.get_user_input_char()
		utils.clear_prompt()
		if ans ~= "y" then
			return
		end
	end
	local fd = luv.fs_open(file, "w", 420)
	luv.fs_write(fd, "# " .. name .. "\n")
	luv.fs_close(fd)
	return uuid
end

M.add = function(state)
	local tree = state.tree
	local node = get_folder_node(tree)
	local in_directory = node:get_id()

	inputs.input('Enter name for new file or directory (dirs end with a "/"):', "", function(destination)
		local is_cat = vim.endswith(destination, "/")
		local dest_uuid
		if is_cat then
			dest_uuid = mainlibdb.add_cat(in_directory, destination.sub(destination, 1, #destination - 1))
		else
			dest_uuid = create_article(state.working_dir, in_directory, destination)
		end

		vim.schedule(function()
			events.fire_event(events.FILE_ADDED, dest_uuid)
			note.navigate(state, nil, dest_uuid)
		end)
	end)
end

-- cc._add_common_commands(M)
return M
