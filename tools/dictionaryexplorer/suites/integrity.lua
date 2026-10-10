--[[
What happens with dictionary files that are not what they should be, and with
the index cache. It runs on what fixtures/make.lua puts outside the dictionary
folder (DE_INTEGRITY), so the other suites never see these files.

  incomplete files   an .idx cut short (with and without idxfilesize in the
                     .ifo), a wordcount that does not match, a .dict or .dict.dz
                     cut short, a .dict.dz shorter than the .idx needs though
                     its last chunk has room, a .dict.dz with a malformed chunk
                     table: the dictionary is refused up front, with a reason
                     and without an error, instead of failing entry by entry,
                     and the plugin then stops offering it
  cut later          a dictionary indexed while whole, whose .dict or .dict.dz
                     is then replaced by a shorter copy, is refused when its
                     cache is loaded
  short reads        readDefinition() of an entry past the end returns nil, not
                     fewer bytes
  cache names        two dictionaries with the same file name, .idx size and
                     date get a cache each, and each finds its own words
  cache contents     a cache that does not add up, or was cut short, is ignored
                     and rebuilt; writing one leaves no temporary file, and the
                     cache file of older versions is removed
]]

return function(H, ui)
	local lfs = require("libs/libkoreader-lfs")
	local root = os.getenv("DE_INTEGRITY")
	local module_path = os.getenv("DE_TOOLS") .. "/../../dictionaryexplorer.koplugin/modules/stardict.lua"
	local StarDict = H.StarDict

	if not (root and lfs.attributes(root .. "/twin_a/twin.ifo", "mode") == "file") then
		H.skip("dictionary integrity", "the integrity fixtures were not made (run the suite with run.sh)")
		H.finish()
		return
	end

	local function ifo(name, base)
		return string.format("%s/%s/%s.ifo", root, name, base or name)
	end

	local function exists(path)
		return lfs.attributes(path, "mode") == "file"
	end

	local function readFile(path)
		local file = io.open(path, "rb")
		local content = file:read("*a")
		file:close()
		return content
	end

	local function writeFile(path, content)
		local file = io.open(path, "wb")
		file:write(content)
		file:close()
	end

	-- ---- incomplete files ----------------------------------------------------
	H.step(1, function()
		local dictionary, reason = StarDict.get(ifo("truncated_idx"))
		H.check("an .idx shorter than its .ifo says is refused up front", dictionary == nil and reason == "incomplete", reason)

		for _index, case in ipairs({
			{ "truncated_idx_noinfo", "truncated index", "an .idx cut in the middle of a record (no idxfilesize to tell)" },
			{ "wrong_count", "incomplete index", "an .idx with fewer entries than the .ifo's wordcount" },
			{ "truncated_dict", "truncated definitions", "a .dict shorter than what the .idx points into" },
			{ "truncated_dz", "truncated definitions", "a .dict.dz whose chunks are not all there" },
			{ "short_dz", "truncated definitions", "a .dict.dz shorter than the .idx needs, though its last chunk has room" },
			{ "malformed_ra", "invalid dictzip header", "a .dict.dz whose chunk table is too short" },
		}) do
			local name, expected, description = case[1], case[2], case[3]
			local broken = StarDict.get(ifo(name))
			if not broken then
				H.check(description .. " opens until it is indexed", false)
			else
				local called, ok, err = pcall(broken.buildIndex, broken)
				if not called then
					ok, err = false, "error: " .. tostring(ok)
				end
				H.check(description .. " is refused when indexed", called and not ok and err == expected and broken.index_error == expected, err)
				H.check(description .. ": no cache is written", not exists(broken.cache_path))
			end
		end

		-- The plugin stops offering a dictionary that failed.
		local plugin = ui.dictionaryexplorer
		if plugin then
			local broken = StarDict.get(ifo("wrong_count"))
			plugin.resolved = plugin.resolved or {}
			plugin.resolved[broken.name] = broken
			H.check("the plugin no longer offers a dictionary that could not be indexed", plugin:getDictionary(broken.name) == nil and not plugin:canOpen(broken.name))
			plugin.resolved[broken.name] = nil
		else
			H.skip("the plugin no longer offers a broken dictionary", "the plugin is not active (it needs KOReader v2026.07 or newer)")
		end
	end)

	-- ---- short reads -----------------------------------------------------------
	H.step(0.5, function()
		for _index, name in ipairs({ "truncated_dict", "truncated_dz", "malformed_ra" }) do
			local broken = StarDict.get(ifo(name))
			local suffix = broken.compressed and ".dict.dz" or ".dict"
			local size = lfs.attributes(string.format("%s/%s/%s%s", root, name, name, suffix), "size")
			-- An entry that starts inside what is left and ends past it.
			local called, definition, err = pcall(broken.readDefinition, broken, { word = "past the end", offset = math.max(size - 40, 0), size = 4000 })
			if not called then
				definition, err = nil, nil
			end
			H.check(name .. ": reading past the end gives nil and a reason, not fewer bytes", definition == nil and err ~= nil, err)
			broken:releaseCaches()
		end
	end)

	-- ---- cut later ---------------------------------------------------------------
	H.step(0.5, function()
		for _index, name in ipairs({ "cut_after_index", "cut_after_index_dz" }) do
			local path = ifo(name)
			local dictionary = StarDict.get(path)
			H.check(name .. ": indexes while whole", dictionary:buildIndex())
			H.check(name .. ": and its cache loads while whole", dofile(module_path).get(path):isIndexed())
			local definitions = dictionary.dict_path
			writeFile(definitions, readFile(definitions):sub(1, math.floor(lfs.attributes(definitions, "size") / 2)))
			local fresh = dofile(module_path).get(path)
			H.check(name .. ": once its definitions are cut, the cache is not used", not fresh:isIndexed())
			local ok, err = fresh:buildIndex()
			H.check(name .. ": and indexing again refuses it", not ok and err == "truncated definitions", err)
		end
	end)

	-- ---- cache names -----------------------------------------------------------
	H.step(0.5, function()
		local a_ifo, b_ifo = ifo("twin_a", "twin"), ifo("twin_b", "twin")
		local a_idx, b_idx = a_ifo:gsub("%.ifo$", ".idx"), b_ifo:gsub("%.ifo$", ".idx")
		H.check("the twins have the same file name and .idx size", lfs.attributes(a_idx, "size") == lfs.attributes(b_idx, "size"))
		-- The same date too, which is all an older cache could tell them apart by.
		local now = os.time()
		lfs.touch(a_idx, now, now)
		lfs.touch(b_idx, now, now)

		local a, b = StarDict.get(a_ifo), StarDict.get(b_ifo)
		H.check("each twin has its own cache file", a.cache_path ~= b.cache_path, a.cache_path:match("[^/]+$") .. " / " .. b.cache_path:match("[^/]+$"))

		-- A cache file of an older version, named after the file alone.
		require("util").makePath(a.legacy_cache_path:match("^(.*)/[^/]+$"))
		writeFile(a.legacy_cache_path, "return {}\n")
		H.check("both twins index", a:buildIndex() and b:buildIndex())
		H.check("indexing leaves no temporary file", not exists(a.cache_path .. ".tmp") and not exists(b.cache_path .. ".tmp"))
		H.check("the cache file of older versions is removed", not exists(a.legacy_cache_path))

		-- Fresh copies of the module only have the caches to go by.
		local fresh_a, fresh_b = dofile(module_path).get(a_ifo), dofile(module_path).get(b_ifo)
		H.check("both caches load", fresh_a:isIndexed() and fresh_b:isIndexed())
		local position_a, exact_a = fresh_a:locate("alfa150")
		local position_b, exact_b = fresh_b:locate("beta150")
		H.check(
			"from its cache, each twin finds its own words",
			exact_a and exact_b and fresh_a:getEntry(position_a).word == "alfa150" and fresh_b:getEntry(position_b).word == "beta150"
				and fresh_a:readDefinition(fresh_a:getEntry(position_a)) == "Twin A entry 150."
				and fresh_b:readDefinition(fresh_b:getEntry(position_b)) == "Twin B entry 150."
		)
	end)

	-- ---- cache contents --------------------------------------------------------
	H.step(0.5, function()
		local a_ifo = ifo("twin_a", "twin")
		local cache_path = StarDict.get(a_ifo).cache_path
		local good = readFile(cache_path)

		-- Valid Lua, but the pages do not add up to the count.
		local tampered, changed = good:gsub('%["count"%] = (%d+)', function(count)
			return '["count"] = ' .. (tonumber(count) + 200)
		end, 1)
		writeFile(cache_path, tampered)
		H.check("a cache whose pages do not add up is ignored", changed == 1 and not dofile(module_path).get(a_ifo):isIndexed())

		-- Cut in the middle, as an interrupted write would have left it.
		writeFile(cache_path, good:sub(1, math.floor(#good / 2)))
		local fresh = dofile(module_path).get(a_ifo)
		H.check("a cache cut short is ignored", not fresh:isIndexed())
		H.check("and the index is rebuilt", fresh:buildIndex() and dofile(module_path).get(a_ifo):isIndexed())
	end)

	H.finish()
end
