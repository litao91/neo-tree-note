local M = {}
local note_items = require("neo-tree-note.lib.note-items")
local renderer = require("neo-tree.ui.renderer")
local utils = require("neo-tree.utils")
local note_utils = require("neo-tree-note.lib.utils")
local mainlibdb = require("neo-tree-note.lib.mainlibdb")
local log = require("neo-tree.log")
local uv = vim.loop

local sep = "/"

local on_category_loaded = function(context, current_uuid)
	local scanned_cat = context.categories[current_uuid]
	if scanned_cat then
		scanned_cat.loaded = true
	end
end

local read_first_line = function(path)
	local line = ""
	local fd = uv.fs_open(path, "r", 438)
	local read_inner = function(fd)
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
	local line = read_inner(fd)
	uv.fs_close(fd)
	return line
end

local get_article_title = function(context, uuid)
	local article_file_path = note_utils.get_article_file_path(context.state, uuid)
	local title = read_first_line(article_file_path)
	title = string.gsub(title, "^#+ ", "")
	return title
end
-- job complete => show the nodes
local job_complete = function(context)
	local state = context.state
	local root = context.root
	local parent_id = context.parent_id
	note_items.deep_sort(root.children)
	if parent_id then
		-- lazy loading a child folder
		renderer.show_nodes(root.children, state, parent_id, context.callback)
	else
		-- full render of the tree
		renderer.show_nodes({ root }, state, nil, context.callback)
	end

	context.state = nil
	context.callback = nil
	context.all_items = nil
	context.root = nil
	context.parent_id = nil
	context = nil
end

local function scan(context, uuid, name)
	log.trace("scan: ", uuid, name)
	-- prepend the root path
	table.insert(context.paths_to_load, 1, { uuid = uuid, name = name })
	-- print("p to load" .. vim.inspect(context.paths_to_load))

	context.categories_scanned = 0
	context.categories_to_scan = #context.paths_to_load

	-- from https://github.com/nvim-lua/plenary.nvim/blob/master/lua/plenary/scandir.lua
	local function read_cat(cur_cat_uuid, current_name, ctx)
		-- print(cur_cat_uuid, current_name)
		local sub_cats = mainlibdb.get_cat_by_pid(cur_cat_uuid)
		local sub_articles = mainlibdb.get_articles_by_cat(cur_cat_uuid)
		for _, node in ipairs(sub_cats) do
			if node.uuid ~= nil then
				-- note_items.create_item(ctx, node.uuid, node.name, "directory")
				local success, item = pcall(note_items.create_item, ctx, node.uuid, node.name, "directory")
				if success then
					if ctx.recursive then
						ctx.categories_to_scan = ctx.categories_to_scan + 1
						table.insert(ctx.paths_to_load, { uuid = item.id, name = item.name })
					end
				else
					log.error("Error creating dir from ", current_name)
				end
			end
		end
		for _, node in ipairs(sub_articles) do
			if node and node.uuid then
				local title = get_article_title(ctx, node.uuid)
				local success, _ = pcall(note_items.create_item, ctx, node.uuid, title, "file")
				if not success then
					log.error("Error creating file from ", node.name)
				end
			end
		end
		on_category_loaded(ctx, cur_cat_uuid)
		ctx.categories_scanned = ctx.categories_scanned + 1
		if ctx.categories_scanned == #ctx.paths_to_load then
			job_complete(ctx)
		end
	end

	--local first = table.remove(context.paths_to_load)
	--local success, err = pcall(read_dir, first)
	--if not success then
	--  log.error(first, ": ", err)
	--end
	for i = 1, context.categories_to_scan do
		read_cat(context.paths_to_load[i].uuid, context.paths_to_load[i].name, context)
	end
end

M.get_items = function(state, parent_uuid, parent_name, uuid_to_reveal, callback, async, recursive)
	local context = note_items.create_context(state)
	context.state = state
	context.parent_id = parent_uuid
	context.uuid_to_reveal = uuid_to_reveal
	context.recursive = recursive
	context.callback = callback

	-- Create root folder
	local root = note_items.create_item(context, parent_uuid or state.uuid, parent_name or state.name, "directory")
	root.loaded = true
	root.search_pattern = state.search_pattern
	context.root = root
	context.categories[root.id] = root
	state.default_expanded_nodes = state.force_open_folders or { state.id }

	if state.search_pattern then
		log.error("Unimplemented")
	else
		-- In the case of a refresh or navigating up, we need to make sure that all
		-- open folders are loaded.
		local uuid = parent_uuid or state.uuid
		local name = parent_name or state.name

		-- init paths to load
		context.paths_to_load = {}
		if parent_uuid == nil then
			if utils.truthy(state.force_open_folders) then
				for _, f in ipairs(state.force_open_folders) do
					local cat_obj = mainlibdb.get_cat_by_uuid(f)
					if cat_obj then
						table.insert(context.paths_to_load, { uuid = uuid, name = cat_obj.name })
					end
				end
			elseif state.tree then
				local expanded = renderer.get_expanded_nodes(state.tree, uuid)
				-- TODO: faster with batch query
				for _, expanded_uuid in ipairs(expanded) do
					local cat_obj = mainlibdb.get_cat_by_uuid(expanded_uuid)
					if cat_obj then
						table.insert(context.paths_to_load, { uuid = expanded_uuid, name = cat_obj.name })
					end
				end
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
					-- local current_path = utils.path_join(acc, part.uuid)
					table.insert(context.paths_to_load, { uuid = part.uuid, name = part.name })
					table.insert(state.default_expanded_nodes, part.uuid)
				end)
				context.paths_to_load = utils.unique(context.paths_to_load)
				-- print("paths to load", vim.inspect(context.paths_to_load))
			end
		end
		scan(context, uuid, name)
	end
end

return M
