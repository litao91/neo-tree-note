local M = {}
local note_items = require("neo-tree-note.lib.note-items")
local renderer = require("neo-tree.ui.renderer")
local utils = require("neo-tree.utils")
local note_utils = require("neo-tree-note.lib.utils")
local mainlibdb = require("neo-tree-note.lib.mainlibdb")
local log = require("neo-tree.log")
local uv = vim.loop

local sep = "/"

local on_category_loaded = function(context, uuid_path)
	local _, current_uuid = utils.split_path(uuid_path)
	local scanned_cat = context.categories[current_uuid]
	if scanned_cat then
		scanned_cat.loaded = true
	end
end

local read_first_line = function(path)
	local line = ""
	local fd = uv.fs_open(path, "r", 438)
	if not fd then
		return ""
	end
	while true do
		local buffer = uv.fs_read(fd, 100, -1)
		if buffer == nil or buffer == "" then
			return line
		end
		local pos = string.find(buffer, "\n")
		if pos == nil then
			line = line .. buffer
		else
			line = line .. string.sub(buffer, 1, pos - 1)
			return line
		end
	end
end

local get_article_title = function(context, uuid)
	local article_file_path = note_utils.get_article_file_path(context.state, uuid)
	local title = read_first_line(article_file_path)
	title = string.gsub(title, "^#+ ", "")
	return title
end

local function async_scan(context, uuid_path, name)
	log.trace("async_scan: ", uuid_path)
	-- prepend the root path
	table.insert(context.paths_to_load, 1, { uuid_path = uuid_path, name = name })

	local categories_scanned = 0
	local categories_to_scan = #context.paths_to_load

	local on_exit = vim.schedule_wrap(function()
		context.job_complete()
	end)

	-- from https://github.com/nvim-lua/plenary.nvim/blob/master/lua/plenary/scandir.lua
	local function read_cat(current_uuid_path, current_name)
		local _, cur_cat_uuid = utils.split_path(current_uuid_path)
		local sub_cats = mainlibdb.get_cat_by_pid(cur_cat_uuid)
		local sub_articles = mainlibdb.get_articles_by_cat(cur_cat_uuid)
		for _, node in ipairs(sub_cats) do
			local uuid_path_entry = current_uuid_path .. sep .. node.uuid
			if node.uuid ~= nil then
				local success, item = pcall(note_items.create_item, context, uuid_path_entry, node.name, "directory")
				if success then
					if context.recursive then
						categories_to_scan = categories_to_scan + 1
						read_cat(item.uuid_path, item.name)
					end
				else
					log.error("Error creating item from ", current_name)
				end
			end
		end
		for _, node in ipairs(sub_articles) do
			if node and node.uuid then
				local uuid_path_entry = current_uuid_path .. sep .. node.uuid
				if node.uuid ~= nil then
					local title = get_article_title(context, node.uuid)
					local success, _ = pcall(note_items.create_item, context, uuid_path_entry, title, "file")
					if not success then
						log.error("Error creating item from ", node.name)
					end
				end
			end
		end
		on_category_loaded(context, current_uuid_path)
		categories_scanned = categories_scanned + 1
		if categories_scanned == #context.paths_to_load then
			on_exit()
		end
	end

	--local first = table.remove(context.paths_to_load)
	--local success, err = pcall(read_dir, first)
	--if not success then
	--  log.error(first, ": ", err)
	--end
	for i = 1, categories_to_scan do
		read_cat(context.paths_to_load[i].uuid_path, context.paths_to_load[i].name)
	end
end

M.get_items = function(state, parent_uuid_path, parent_name, uuid_to_reveal, callback, async, recursive)
	local context = note_items.create_context(state)
	context.uuid_to_reveal = uuid_to_reveal
	context.recursive = recursive

	-- Create root folder
	local root =
		note_items.create_item(context, parent_uuid_path or state.uuid_path, parent_name or state.name, "directory")
	root.loaded = true
	root.search_pattern = state.search_pattern
	context.categories[root.id] = root
	state.default_expanded_nodes = state.force_open_folders or { state.path }

	-- job complete => show the nodes
	context.job_complete = function()
		note_items.deep_sort(root.children)
		if parent_uuid_path then
			-- lazy loading a child folder
			renderer.show_nodes(root.children, state, parent_uuid_path, callback)
		else
			-- full render of the tree
			renderer.show_nodes({ root }, state, nil, callback)
		end
	end

	if state.search_pattern then
		log.error("Unimplemented")
	else
		-- In the case of a refresh or navigating up, we need to make sure that all
		-- open folders are loaded.
		local uuid_path = parent_uuid_path or state.uuid_path
		local name = parent_name or state.name_path

		-- init paths to load
		context.paths_to_load = {}
		if parent_uuid_path == nil then
			if utils.truthy(state.force_open_folders) then
				for _, f in ipairs(state.force_open_folders) do
					table.insert(context.paths_to_load, f)
				end
			elseif state.tree then
				local _, uuid = utils.split_path(state.uuid_path)
				context.paths_to_load = renderer.get_expanded_nodes(state.tree, uuid)
			end
			if uuid_to_reveal then
				local cat_of_article = mainlibdb.find_cat_of_article(uuid_to_reveal)
				local is_article = cat_of_article ~= nil
				local uuid_path_to_reveal
				if is_article then
					uuid_path_to_reveal = mainlibdb.find_virtual_uuid_name_path_of_cat(cat_of_article)
				else
					uuid_path_to_reveal = mainlibdb.find_virtual_uuid_name_path_of_cat(uuid_to_reveal)
					table.remove(uuid_path_to_reveal)
				end
				utils.reduce(uuid_path_to_reveal, "", function(acc, part)
					local current_path = utils.path_join(acc, part.uuid)
					print(current_path)
					if #current_path > #uuid_path then
						table.insert(context.paths_to_load, { uuid_path = current_path, name = part.name })
						table.insert(state.default_expanded_nodes, { uuid_path = current_path, name = part.name })
					end
					return current_path
				end)
				context.paths_to_load = utils.unique(context.paths_to_load)
			end
		end
		async_scan(context, uuid_path, name)
	end
end

return M
