local M = {}
local note_items = require("neo-tree-note.lib.note-items")
local renderer = require("neo-tree.ui.renderer")
local utils = require("neo-tree.utils")
local mainlibdb = require("neo-tree-note.lib.mainlibdb")
local log = require("neo-tree.log")

local sep = "/"

local on_category_loaded = function(context, uuid_path)
	local _, current_uuid = utils.split_path(uuid_path)
	local scanned_cat = context.categories[current_uuid]
	if scanned_cat then
		scanned_cat.loaded = true
	end
end

local function async_scan(context, uuid_path, name_path)
	log.trace("async_scan: ", uuid_path)
	-- prepend the root path
	table.insert(context.paths_to_load, 1, { uuid_path = uuid_path, name_path = name_path })
	print(vim.inspect(context.paths_to_load))

	local categories_scanned = 0
	local categories_to_scan = #context.paths_to_load

	local on_exit = vim.schedule_wrap(function()
		context.job_complete()
	end)

	-- from https://github.com/nvim-lua/plenary.nvim/blob/master/lua/plenary/scandir.lua
	local function read_cat(current_uuid_path, current_name_path)
		local _, cur_cat_uuid = utils.split_path(current_uuid_path)
		local sub_cats = mainlibdb.get_cat_by_pid(cur_cat_uuid)
		local sub_articles = mainlibdb.get_articles_by_cat(cur_cat_uuid)
		for _, node in ipairs(sub_cats) do
			local uuid_path_entry = current_uuid_path .. sep .. node.uuid
			local name_path_entry = current_name_path .. sep .. node.name
			if node.uuid ~= nil then
				local success, item =
					pcall(note_items.create_item, context, uuid_path_entry, name_path_entry, "directory")
				if success then
					if context.recursive then
						categories_to_scan = categories_to_scan + 1
						read_cat(item.uuid_path, item.name_path)
					end
				else
					log.error("Error creating item from ", current_name_path)
				end
			end
		end
		for _, node in ipairs(sub_articles) do
			local uuid_path_entry = current_uuid_path .. sep .. node.uuid
			local name_path_entry = current_name_path .. sep .. node.name
			if node.uuid ~= nil then
				local success, _ = pcall(note_items.create_item, context, uuid_path_entry, name_path_entry, "file")
				if not success then
					log.error("Error creating item from ", current_name_path)
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
		print(i)
		read_cat(context.paths_to_load[i].uuid_path, context.paths_to_load[i].name_path)
	end
end
M.get_items = function(state, parent_uuid_path, parent_name_path, uuid_to_reveal, callback, async, recursive)
	local context = note_items.create_context(state)
	context.uuid_to_reveal = uuid_to_reveal
	context.recursive = recursive

	-- Create root folder
	local root = note_items.create_item(
		context,
		parent_uuid_path or state.uuid_path,
		parent_name_path or state.name_path,
		"directory"
	)
	root.loaded = true
	root.search_pattern = state.search_pattern
	context.categories[root.id] = root
	state.default_expanded_nodes = state.force_open_folders or { state.path }

	-- job complete => show the nodes
	context.job_complete = function()
		note_items.deep_sort(root.children)
		if parent_uuid_path then
			-- lazy loading a child folder
			renderer.show_nodes(root.children, state, parent_name_path, callback)
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
		local uuid_path = parent_uuid or state.uuid_path
		local name_path = parent_name_path or state.name_path

		-- init paths to load
		context.paths_to_load = {}
		if parent_uuid == nil then
			if utils.truthy(state.force_open_folders) then
				for _, f in ipairs(state.force_open_folders) do
					table.insert(context.paths_to_load, f)
				end
			elseif state.tree then
				local _, uuid = utils.split_path(state.uuid_path)
				context.paths_to_load = renderer.get_expanded_nodes(state.tree, uuid)
			end
			if uuid_to_reveal then
				log.error("Unimplemented")
			end
		end
		async_scan(context, uuid_path, name_path)
	end
end

return M
