local utils = require("neo-tree.utils")

local create_item, set_parents

function create_item(context, uuid_path, name_path, _type)
	local uuid_parent, uuid = utils.split_path(uuid_path)
	if context.categories[uuid] then
		return context.categories[uuid]
	end
	local name_parent, name = utils.split_path(name_path)
	local item = {
		id = uuid,
		name = name,
		uuid_parent = uuid_parent,
		name_parent = name_parent,
		uuid_path = uuid_path,
		path = name_path,
		type = _type,
	}
	if item.type == "directory" then
		item.children = {}
		item.loaded = false
		context.categories[uuid] = item
		if context.state.search_pattern then
			table.insert(context.state.default_expanded_nodes, item.id)
		end
	end
	set_parents(context, item)
	if not context.all_items then
		context.all_items = {}
	end
	local is_not_root = (uuid_path ~= "0")
	if is_not_root then
		table.insert(context.all_items, item)
	end
	return item
end

local function sort_items(a, b)
	if a.type == b.type then
		return a.path < b.path
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
function get_name(path)
	local _, uuid = utils.split_path(path)
	return uuid
end
function set_parents(context, item)
	if context.item_exists[item.id] then
		return
	end
	if not item.uuid_path then
		return
	end

	local parent = context.categories[get_name(item.uuid_parent)]
	-- parent already created
	if not utils.truthy(item.uuid_parent) then
		return
	end
	if parent == nil then
		local success
		success, parent = pcall(create_item, context, item.uuid_parent, item.name_parent, "directory")
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
