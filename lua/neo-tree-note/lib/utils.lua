local utils = require("neo-tree.utils")

local get_article_file_path = function(state, uuid)
	return utils.path_join(state.working_dir, "docs", uuid .. ".md")
end

return {
	get_article_file_path = get_article_file_path,
}
