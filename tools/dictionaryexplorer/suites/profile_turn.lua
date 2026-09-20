--[[
Where the time of a page turn goes, function by function (inclusive times), for
one dictionary. Use it to see what to optimise next.

  DE_DICT=Oxford    which dictionary, by a part of its name (default: Portuguesa)
  DE_TRAIL=1        with the breadcrumb showing (the trail and the back / forward buttons)

The MuPDF line is the layout engine itself; _fitPage minus MuPDF is the
plugin's own work around it.
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
		H.skip("profile of a page turn", "no dictionary matching '" .. wanted .. "'")
		H.finish()
		return
	end

	local Viewer, StarDict = H.Viewer, H.StarDict
	H.profile(StarDict, "readDefinition", "readDefinition")
	H.profile(StarDict, "getEntry", "getEntry")
	H.profile(Viewer, "showNext", "showNext (the whole page turn)")
	H.profile(Viewer, "_fitPage", "_fitPage (all the layouts of the turn)")
	H.profile(Viewer, "_buildHtmlWidget", "_buildHtmlWidget (reads + conversion + MuPDF)")
	H.profile(Viewer, "_readHtml", "  _readHtml (read + prepare the text)")
	H.profile(require("modules/text"), "xdxfLiteToHtml", "    Text.xdxfLiteToHtml (the \"x\" conversion)")
	H.profile(require("modules/text"), "plainToHtml", "    Text.plainToHtml")
	H.profile(require("ui/widget/htmlboxwidget"), "setContent", "MuPDF setContent (parse + layout)")
	H.profile(Viewer, "_installPage", "_installPage (header, buttons, breadcrumb)")
	H.profile(Viewer, "_buildHeader", "  _buildHeader")
	H.profile(Viewer, "_buildButtons", "  _buildButtons")
	H.profile(Viewer, "_buildBreadcrumb", "  _buildBreadcrumb")

	H.step(1, function()
		local viewer = H.newViewer(dictionary, "livro")
		if os.getenv("DE_TRAIL") then
			for _index, word in ipairs({ "amor", "correr", "mesa", "gato" }) do
				viewer:goToWord(word)
			end
		end
		H.resetTimers()
		collectgarbage("collect")
		local turns = 30
		local started = os.clock()
		for _turn = 1, turns do
			viewer:showNext()
		end
		H.say(string.format("%s%s: %d page turns, %.2f ms each (CPU)", dictionary.name, os.getenv("DE_TRAIL") and " (with the trail)" or "", turns, (os.clock() - started) / turns * 1000))
		H.printTimers(turns, "turn")
		viewer:onCloseWidget()
	end)

	H.finish()
end
