--[[
Every layout attempt of the first page turns, and what the fit model thought of
it: how many entries (n), how many groups of identical text (g) and bytes were
laid out, whether the page fitted and how full it was, and what the model had
predicted. The model's two numbers are printed after each turn, so you can see
it learn: `a` is the pixels an entry costs on its own, `c` the pixels per byte.

Use it to see why a dictionary needs more layouts than it should (a prediction
that is far off, or noisy).

  DE_DICT=Oxford    which dictionary, by a part of its name (default: Portuguesa)
]]

return function(H, ui)
	local wanted = os.getenv("DE_DICT") or "Portuguesa"
	local dictionary
	for _index, candidate in ipairs(H.dictionaries().list) do
		if candidate.name:find(wanted, 1, true) then
			dictionary = candidate
		end
	end
	if not dictionary then
		H.skip("fit log", "no dictionary matching '" .. wanted .. "'")
		H.finish()
		return
	end

	local attempts = {}
	local build = H.Viewer._buildHtmlWidget
	H.Viewer._buildHtmlWidget = function(viewer, first, last, height)
		local widget = build(viewer, first, last, height)
		local box = widget.htmlbox_widget
		local used = box:getSinglePageHeight()
		local predicted = (viewer:_getFitModel():predict(widget.fit_groups, widget.fit_bytes) + widget.fit_extra) / height * 100
		attempts[#attempts + 1] = string.format(
			"n=%d(g%d,%dB) %s pred=%.0f%%", last - first + 1, widget.fit_groups, widget.fit_bytes,
			used and string.format("fits %3.0f%%", 100 * used / height) or ("OVERFLOW p" .. box.page_count), predicted
		)
		return widget
	end

	H.step(1, function()
		local viewer = H.Viewer:new({
			dictionary = dictionary,
			position = math.floor(dictionary:getCount() * 0.3),
			side_margins = { left = 30, right = 30 },
		})
		local model = viewer:_getFitModel()
		H.say(string.format("%s. Prior after sampling the first entries: a=%.1f px, c=%.4f px/byte", dictionary.name, model.prior_entry, model.prior_byte))
		for turn = 1, 22 do
			attempts = {}
			viewer:showNext()
			H.say(string.format("turn %2d  a=%5.1f c=%.4f | %d layout(s): %s", turn, model.per_entry, model.per_byte, #attempts, table.concat(attempts, "  ->  ")))
		end
		viewer:onCloseWidget()
	end)

	H.finish()
end
