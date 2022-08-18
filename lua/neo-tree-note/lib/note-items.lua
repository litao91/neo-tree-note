local utils = require("neo-tree.utils")

local mainlibdb = require("neo-tree-note.lib.mainlibdb")
local create_item, set_parents

function create_item(context, uuid, name, _type)
	if context.categories[uuid] then
		return context.categories[uuid]
	end
	local item = {
		id = uuid,
		name = name,
		type = _type,
	}
	if item.type == "directory" then
		item.children = {}
		item.loaded = false
		context.categories[uuid] = item
		if context.state.search_pattern then
			table.insert(context.state.default_expanded_nodes, item.id)
		end
	else
		item.ext = "md"
	end
	set_parents(context, item)
	if not context.all_items then
		context.all_items = {}
	end
	local is_not_root = (uuid ~= "0")
	if is_not_root then
		table.insert(context.all_items, item)
	end
	return item
end

local function sort_items(a, b)
	if a.type == b.type then
		return a.name < b.name
	else
		return a.type < b.type
	end
end

local function sort_items_case_insensitive(a, b)
	if a.type == b.type then
		return a.path:lower() < b.path:lower()
	else
		return a.type < b.type
	end
end

local function sort_function_is_valid(func)
	if func == nil then
		return false
	end

	local a = { type = "dir", path = "foo" }
	local b = { type = "dir", path = "baz" }

	local success, result = pcall(func, a, b)
	if success and type(result) == "boolean" then
		return true
	end

	log.error("sort function isn't valid ", result)
	return false
end
local function deep_sort(tbl, sort_func)
	if sort_func == nil then
		local config = require("neo-tree").config
		if sort_function_is_valid(config.sort_function) then
			sort_func = config.sort_function
		elseif config.sort_case_insensitive then
			sort_func = sort_items_case_insensitive
		else
			sort_func = sort_items
		end
	end
	table.sort(tbl, sort_func)
	for _, item in pairs(tbl) do
		if item.type == "directory" then
			deep_sort(item.children, sort_func)
		end
	end
end

function set_parents(context, item)
	if context.item_exists[item.id] then
		return
	end

	local parent_uuid = mainlibdb.find_parent_uuid(item.id)
	require'neo-tree.log'.trace("parent of " .. item.id .. " " .. vim.inspect(parent_uuid))
	if not parent_uuid then
		return
	end
	local parent = context.categories[parent_uuid]
	-- parent already created
	if parent == nil then
		local success
		local parent_name = "/"
		if parent_uuid ~= "0" then
			local parent_obj = mainlibdb.get_cat_by_uuid(parent_uuid)
			parent_name = parent_obj.name
		end
		success, parent = pcall(create_item, context, parent_uuid, parent_name, "directory")
		if not success then
			log.error("error creating item for ", item.name_parent)
		end
		context.categories[parent.id] = parent
		set_parents(context, parent)
	end
	table.insert(parent.children, item)
	context.item_exists[item.id] = true

	if item.filtered_by == nil and type(parent.filtered_by) == "table" then
		item.filtered_by = vim.deepcopy(parent.filtered_by)
	end
end

local create_context = function(state)
	return {
		state = state,
		categories = {},
		item_exists = {},
		all_items = {},
	}
end

return {
	create_context = create_context,
	create_item = create_item,
	deep_sort = deep_sort,
}
