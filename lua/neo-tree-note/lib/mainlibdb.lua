local sqlite = require("sqlite.db")
local M = {}
local math = require("math")
M.config = { working_dir = nil, uri = nil, db = nil }
M.db = nil

local init_or_get_db = function()
	if M.db ~= nil then
		return M.db
	end
	local luv = vim.loop
	if not luv.fs_access(M.config.uri, "r") then
		log.error("Fail to init db at " .. M.config.uri)
		return nil
	end
	-- TODO: create enw db if not exists
	M.db = sqlite:open(M.config.uri)
	math.randomseed(os.clock() * 100000000000)
	return M.db
end

function reverse(t)
	local n = #t
	local i = 1
	while i < n do
		t[i], t[n] = t[n], t[i]
		i = i + 1
		n = n - 1
	end
end

function M.get_node_type(uuid)
	return init_or_get_db():with_open(function(db)
		local r1 = db:eval("select count(*) as cnt from cat where uuid = ?", uuid)
		if r1 ~= nil and r1[1] ~= nil and r1[1].cnt > 0 then
			return "directory"
		end
		local r2 = db:eval("select count(*) as cnt from article where uuid = ?", uuid)
		if r2 ~= nil and r2[1] ~= nil and r2[1].cnt > 0 then
			return "file"
		end
		return nil
	end)
end

function M.find_virtual_uuid_path(uuid)
	local type = M.get_node_type(uuid)
	if type == "directory" then
		return M.find_virtual_uuid_path_of_cat(uuid)
	elseif type == "file" then
		return M.find_virtual_uuid_path_of_article(uuid)
	else
		return nil
	end
end

function M.find_cat_of_article(article_uuid)
	return init_or_get_db():with_open(function(db)
		local r = db:eval(
			[[
        select CAST(rid as text) as uuid from cat_article where aid = :article_uuid
        ]],
			{ article_uuid = article_uuid }
		)
		if type(r) ~= "boolean" and r ~= nil and r[1] ~= nil then
			return r[1].uuid
		else
			return nil
		end
	end)
end

function M.find_virtual_uuid_path_of_article(article_uuid)
	local path = init_or_get_db():with_open(function(db)
		local r = db:eval(
			[[
        select CAST(rid as text) as uuid from cat_article where aid = :article_uuid
        ]],
			{ article_uuid = article_uuid }
		)
		local path = { { uuid = article_uuid, name = "" } }
		while true do
			if type(r) ~= "boolean" and r[1] ~= nil and r[1].uuid ~= nil then
				table.insert(path, r[1].uuid)
				r = db:eval([[
                select CAST(pid as TEXT) as uuid, name from cat where uuid =
                ]] .. r[1].uuid)
			else
				break
			end
		end
		return path
	end)
	return reverse(path)
end

function M.find_virtual_uuid_path_of_cat(cat_uuid)
	return init_or_get_db():with_open(function(db)
		local path = { cat_uuid }
		local r = db:eval([[
                select CAST(pid as TEXT) as uuid from cat where uuid =
                ]] .. cat_uuid)
		while true do
			if type(r) ~= "boolean" and r[1] ~= nil and r[1].uuid ~= nil then
				table.insert(path, r[1].uuid)
				r = db:eval([[
                select CAST(pid as TEXT) as uuid from cat where uuid =
                ]] .. r[1].uuid)
			else
				break
			end
		end
		reverse(path)
		return path
	end)
end

function M.find_virtual_uuid_name_path_of_cat(cat_uuid)
	return init_or_get_db():with_open(function(db)
		local r = db:eval([[
                select CAST(pid as TEXT) as pid, name from cat where uuid =
                ]] .. cat_uuid)
		local path = { { uuid = cat_uuid } }
		while true do
			if type(r) ~= "boolean" and r[1] ~= nil and r[1].pid ~= nil then
				path[#path].name = r[1].name
				table.insert(path, { uuid = r[1].pid })
				r = db:eval([[
                select CAST(pid as TEXT) as pid, name from cat where uuid =
                ]] .. r[1].pid)
			else
				break
			end
		end
		reverse(path)
		return path
	end)
end

function M.find_paths_to_cat_uuid(cat_uuid)
	return init_or_get_db():with_open(function(db)
		local r = db:eval([[
                select CAST(pid as TEXT) as pid, name from cat where uuid =
                ]] .. cat_uuid)
		local uuid_path = { cat_uuid }
		local name_path = {}

		while true do
			if type(r) ~= "boolean" and r[1] ~= nil and r[1].name ~= nil then
				table.insert(name_path, r[1].name)
			end

			if type(r) ~= "boolean" and r[1] ~= nil and r[1].pid ~= nil then
				table.insert(uuid_path, r[1].pid)
				r = db:eval([[
                select CAST(pid as TEXT) as pid, name from cat where uuid =
                ]] .. r[1].pid)
			else
				break
			end
		end
		reverse(uuid_path)
		reverse(name_path)
		return { uuid_path = uuid_path, name_path = name_path }
	end)
end

function M.find_sub_cat_uuid_by_name(in_uuid, name)
	return init_or_get_db():with_open(function(db)
		local r = db:eval("select uuid from cat where pid = " .. in_uuid .. " and name = '" .. name .. "'")
		if type(r) ~= "boolean" and r[1] ~= nil and r[1].uuid ~= nil then
			return r[1].uuid
		else
			return nil
		end
	end)
end

function M.has_inited()
	return M.db == nil
end

function M.init(opts)
	M.config.working_dir = opts.working_dir
	M.config.uri = opts.working_dir .. "/mainlib.db"
	return true
end

function M.get_categories()
	return M.get_cat_by_pid(0)
end

function M.get_cat_by_uuid(cat_uuid)
	return init_or_get_db():with_open(function(db)
		return db:eval(
			[[
SELECT
    id,
    CAST(pid AS TEXT) AS pid,
    CAST(uuid AS TEXT) as uuid,
    name,
    docName,
    catType,
    sort,
    sortType
FROM cat
WHERE uuid = :uuid
ORDER BY sort
        ]],
			{ uuid = cat_uuid }
		)
	end)
end

function M.update_category_of_article(article_uuid, new_cat_uuid)
	if type(article_uuid) == "string" then
		article_uuid = tonumber(article_uuid)
	end
	if type(new_cat_uuid) == "string" then
		new_cat_uuid = tonumber(new_cat_uuid)
	end
	return init_or_get_db():with_open(function(db)
		return db:eval(
			[[
        update cat_article
        set rid = :new_cat_uuid
        where aid = :article_uuid
        ]],
			{ new_cat_uuid = new_cat_uuid, article_uuid = article_uuid }
		)
	end)
end

function M.rename_cat(uuid, pid, new_name)
	if type(uuid) == "string" then
		uuid = tonumber(uuid)
	end
	if type(pid) == "string" then
		pid = tonumber(pid)
	end
	return init_or_get_db():with_open(function(db)
		return db:eval(
			[[
        update cat
        set name = :new_name, pid = :pid
        where uuid = :uuid
        ]],
			{ uuid = uuid, pid = pid, new_name = new_name }
		)
	end)
end

function M.get_cat_by_name_and_pid(cat_name, pid)
	if type(pid) == "string" then
		pid = tonumber(pid)
	end
	return init_or_get_db():with_open(function(db)
		local r = db:eval(
			[[
SELECT
    id,
    CAST(pid AS TEXT) AS pid,
    CAST(uuid AS TEXT) as uuid,
    name,
    docName,
    catType,
    sort,
    sortType
FROM cat
WHERE name = :name and pid = :pid
ORDER BY sort
        ]],
			{ name = cat_name, pid = pid }
		)
		if type(r) ~= "table" then
			return nil
		else
			return r
		end
	end)
end

function M.get_cat_by_pid(pid)
	if type(pid) == "string" then
		pid = tonumber(pid)
	end
	return init_or_get_db():with_open(function(db)
		local r = db:eval(
			[[
SELECT
    id,
    CAST(pid AS TEXT) AS pid,
    CAST(uuid AS TEXT) as uuid,
    name,
    docName,
    catType,
    sort,
    sortType
FROM cat
WHERE pid = :pid
ORDER BY sort
        ]],
			{ pid = pid }
		)
		if r == true or r[1] == nil or r[1].id == nil then
			return {}
		else
			return r
		end
	end)
end

function M.get_article_by_uuid(aid)
	if type(aid) == "string" then
		aid = tonumber(aid)
	end
	return init_or_get_db():with_open(function(db)
		return db:eval(
			[[
SELECT
    id,
    CAST(article.uuid AS TEXT) as uuid,
    type,
    state,
    sort,
    dateAdd,
    dateModif,
    dateArt,
    docName,
    otherMedia,
    buildResource,
    postExtValue,
    isTop
FROM article
WHERE uuid = ? ORDER BY article.sort desc]],
			aid
		)
	end)
end

function M.get_articles_by_cat(cat_uuid)
	if type(cat_uuid) == "string" then
		cat_uuid = tonumber(cat_uuid)
	end
	return init_or_get_db():with_open(function(db)
		local r = db:eval(
			[[
SELECT
    article.id as id,
    CAST(article.uuid AS TEXT) as uuid,
    type,
    state,
    article.sort as sort,
    dateAdd,
    dateModif,
    dateArt,
    article.docName as docName,
    otherMedia,
    buildResource,
    postExtValue,
    isTop
FROM cat
LEFT JOIN cat_article ON cat.uuid = cat_article.rid
LEFT JOIN article on cat_article.aid = article.uuid
WHERE cat.uuid = ? ORDER BY article.sort desc]],
			cat_uuid
		)
		if r == true or not r[1] or not r[1].id  then
			return {}
		else
			return r
		end
	end)
end

local function gen_uuid()
	local s, ns = vim.loop.gettimeofday()
	local ms = s * 1000 + math.floor(ns / 1000)
	return "" .. ms
end

function M.add_cat(pid, cat_name)
	if type(pid) == "string" then
		pid = tonumber(pid)
	end
	local uuid = gen_uuid()
	init_or_get_db():with_open(function(db)
		local max_sort = db:eval("SELECT MAX(sort) as max_sort FROM cat")[1]

		if max_sort == nil then
			max_sort = 1
		else
			max_sort = max_sort.max_sort
		end
		return db:eval(
			[[
                INSERT INTO cat (
                  pid,
                  uuid,
                  name,
                  docName,
                  catType,
                  sort,
                  sortType,
                  siteURL,
                  siteSkinName,
                  siteLastBuildDate,
                  siteBuildPath,
                  siteFavicon,
                  siteLogo,
                  siteDateFormat,
                  sitePageSize,
                  siteListTextNum,
                  siteName,
                  siteDes,
                  siteShareCode,
                  siteHeader,
                  siteOther,
                  siteMainMenuData,
                  siteExtDef,
                  siteExtValue,
                  sitePostExtDef,
                  siteEnableLaTeX,
                  siteEnableChart)
                VALUES
                 (:pid,:uuid,:name,'',12,:sort,0,'','',0,'','','','',0,0,'','','','','','',
                '','','',0,0)
    ]],
			{ pid = pid, uuid = uuid, name = cat_name, sort = max_sort }
		)
	end)
	return uuid
end

function M.add_article(pid)
	if type(pid) == "string" then
		pid = tonumber(pid)
	end
	local now = os.time(os.date("!*t"))
	local uuid = gen_uuid()
	init_or_get_db():with_open(function(db)
		db:eval(
			[[
        INSERT INTO article(
                uuid,
                "type",
                state,
                sort,
                dateAdd,
                dateModif,
                dateArt,
                docName,
                otherMedia,
                buildResource,
                postExtValue)
            VALUES
                (:uuid, 0, 1, :uuid, :now, :now, :now, '', '', '', '');
        ]],
			{ uuid = uuid, now = now }
		)
		db:eval("INSERT INTO cat_article (rid, aid) VALUES (:pid, :uuid)", { pid = pid, uuid = uuid })
	end)
	return uuid
end

function M.del_article(article_uuid)
	if type(article_uuid) == "string" then
		article_uuid = tonumber(article_uuid)
	end
	init_or_get_db():with_open(function(db)
		db:eval("DELETE from cat_article WHERE aid = :aid", { aid = article_uuid })
		db:eval("DELETE FROM article where uuid = :aid", { aid = article_uuid })
	end)
end
function M.del_cat(cat_uuid)
	if type(cat_uuid) == "string" then
		cat_uuid = tonumber(cat_uuid)
	end
	init_or_get_db():with_open(function(db)
		db:eval("DELETE from cat_article WHERE rid = :rid", { rid = cat_uuid })
		db:eval("DELETE from cat WHERE uuid = :rid", { rid = cat_uuid })
	end)
end
return M
