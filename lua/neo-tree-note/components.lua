-- This file contains the built-in components. Each componment is a function
-- that takes the following arguments:
--      config: A table containing the configuration provided by the user
--              when declaring this component in their renderer config.
--      node:   A NuiNode object for the currently focused node.
--      state:  The current state of the source providing the items.
--
-- The function should return either a table, or a list of tables, each of which
-- contains the following keys:
--    text:      The text to display for this item.
--    highlight: The highlight group to apply to this text.

local highlights = require("neo-tree.ui.highlights")
local common = require("neo-tree.sources.common.components")

local M = {}
local make_two_char = function(symbol)
	if vim.fn.strchars(symbol) == 1 then
		return symbol .. " "
	else
		return symbol
	end
end

M.custom = function(config, node, state)
	local text = node.extra.custom_text or ""
	local highlight = highlights.DIM_TEXT
	return {
		text = text .. " ",
		highlight = highlight,
	}
end

M.icon = function(config, node, state)
	local icon = config.default or " "
	local padding = config.padding or " "
	local highlight = config.highlight or highlights.FILE_ICON
	if node.type == "directory" then
		highlight = highlights.DIRECTORY_ICON
		if node.loaded and not node:has_children() then
			icon = config.folder_empty or config.folder_open or "-"
		elseif node:is_expanded() then
			icon = config.folder_open or "-"
		else
			icon = config.folder_closed or "+"
		end
	elseif node.type == "file" then
		local success, web_devicons = pcall(require, "nvim-web-devicons")
		if success then
			local devicon, hl = web_devicons.get_icon(node.name, "md")
			icon = devicon or icon
			highlight = hl or highlight
		end
	end
	return {
		text = icon .. padding,
		highlight = highlight,
	}
end

M.name = function(config, node, state)
	local highlight = config.highlight or highlights.FILE_NAME
	if node.type == "directory" then
		highlight = highlights.DIRECTORY_NAME
	end
	if node:get_depth() == 1 then
		highlight = highlights.ROOT_NAME
	end
	return {
		text = node.name,
		highlight = highlight,
	}
end
M.modified = function(config, node, state)
	local modified_buffers = state.modified_buffers or {}

	if modified_buffers[node.path] then
		return {
			text = (make_two_char(config.symbol) or "[+] "),
			highlight = config.highlight or highlights.MODIFIED,
		}
	else
		return {}
	end
end

return vim.tbl_deep_extend("force", common, M)
