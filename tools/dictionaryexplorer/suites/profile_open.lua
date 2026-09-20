--[[
Where the time of opening the viewer at a word goes, function by function
(inclusive times), for one dictionary, once everything is warm (fonts loaded,
the fit model already taught, as in a real session).

  DE_DICT=Oxford    which dictionary, by a part of its name (default: Portuguesa)
]]

local WORDS = { "livro", "mesa", "correr", "amor", "casa", "gato", "sol", "cao" }

return function(H, ui)
	local wanted = os.getenv("DE_DICT") or "Portuguesa"
	local dictionary
	for _index, candidate in ipairs(H.dictionaries().list) do
		if candidate.name:find(wanted, 1, true) then
			dictionary = candidate
		end
	end
	if not dictionary then
		H.skip("profile of opening", "no dictionary matching '" .. wanted .. "'")
		H.finish()
		return
	end

	local Viewer = H.Viewer
	H.profile(Viewer, "init", "Viewer:init (the whole opening)")
	H.profile(Viewer, "_getContentHeight", "  _getContentHeight (header + buttons measured)")
	H.profile(Viewer, "_buildHeader", "    _buildHeader")
	H.profile(Viewer, "_buildButtons", "    _buildButtons")
	H.profile(Viewer, "_aroundRanges", "  _aroundRanges (the prediction)")
	H.profile(Viewer, "_sampleVisibleRatio", "  _sampleVisibleRatio (first use only)")
	H.profile(Viewer, "_fitPage", "  _fitPage")
	H.profile(Viewer, "_fillRemaining", "  _fillRemaining")
	H.profile(Viewer, "_buildHtmlWidget", "    _buildHtmlWidget (reads + MuPDF)")
	H.profile(require("ui/widget/htmlboxwidget"), "setContent", "      MuPDF setContent (parse + layout)")
	H.profile(Viewer, "_installPage", "  _installPage")
	H.profile(H.StarDict, "locate", "locate (finding the word)")

	H.step(1, function()
		H.newViewer(dictionary, "sol"):onCloseWidget() -- warm-up
		H.resetTimers()
		local started = os.clock()
		for _index, word in ipairs(WORDS) do
			H.newViewer(dictionary, word):onCloseWidget()
		end
		H.say(string.format("%s: %d openings, %.2f ms each (CPU)", dictionary.name, #WORDS, (os.clock() - started) / #WORDS * 1000))
		H.printTimers(#WORDS, "opening")
	end)

	H.finish()
end
