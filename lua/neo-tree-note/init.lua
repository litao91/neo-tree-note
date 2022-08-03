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
	-- state.dirty = false
	-- if uuid == nil then
	-- 	log.debug("navigate_internal: uuid is nil, using root")
	-- 	uuid = "0"
	-- end
	-- if uuid ~= state.uuid then
	-- 	state.uuid = uuid
	-- end
	state.uuid_path = "0"
	state.name_path = "/"
	vfs_scan.get_items(state, nil, nil, uuid_to_reveal, callback)
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
