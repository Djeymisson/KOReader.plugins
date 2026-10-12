--[[
Translate and Wikipedia: what is queried, what is cached, and how a query runs.

  trapper         queries run under Trapper:wrap, as KOReader's own, so a tap
                  can cancel them; on macOS, where a process forked from the
                  KOReader app dies on its first network access, they run in
                  KOReader's process
  cache           looking the same text up again, in a new carousel, shows the
                  answer with no query; per target language and per Wikipedia
                  language; "nothing found" is cached too
  retry           Retry queries again even when the answer is cached
  errors          a failed query is not cached: the next lookup queries again
  interrupted     a cancelled query says so and offers Retry
  manual          with online cards on "Manual only", a cached answer is shown
                  at once, and anything else waits for the Load button
]]

local PAGE_TRANSLATION, PAGE_WIKIPEDIA = 2, 3

return function(H, ui)
	local plugin = H.plugin
	local fail_translation, fail_wikipedia
	H.stubOnline(function(text, target)
		if fail_translation then
			error(fail_translation)
		end
		return "[" .. tostring(target) .. "] " .. text
	end, function(text)
		if fail_wikipedia then
			error(fail_wikipedia)
		end
		if text == "qqqzzzz" then
			return {}
		end
		return { { title = text, extract = "An article about " .. text .. "." } }
	end)

	local function translate(word)
		H.step(0.5, function()
			H.holdWord(word)
		end)
		H.step(0.5, function()
			ui.highlight:translate()
		end)
	end

	local function wikipedia(word)
		H.step(0.5, function()
			H.holdWord(word)
		end)
		H.step(0.5, function()
			ui.highlight:lookupWikipedia()
		end)
	end

	local function translationText()
		local payload = plugin:getPagePayload(plugin.current_state, PAGE_TRANSLATION, true)
		return payload.html_body
	end

	-- ---- trapper and cache: translation --------------------------------------
	H.step(0.3, function()
		H.check("queries use a subprocess except on macOS", plugin.online_queries_in_subprocess == (jit.os ~= "OSX"), jit.os)
		-- As on an e-reader, whatever runs the suite.
		plugin.online_queries_in_subprocess = true
	end)
	translate("casa")
	H.step(1, function()
		H.check("the first translation queries", H.calls.translation == 1, H.calls.translation)
		H.check("under Trapper:wrap, so a tap can cancel it", H.calls.wrapped == 1 and H.calls.unwrapped == 0, H.calls.wrapped .. " wrapped, " .. H.calls.unwrapped .. " not")
		H.closeCarousel()
	end)
	translate("casa")
	H.step(1, function()
		H.check("translating it again needs no query", H.calls.translation == 1, H.calls.translation)
		H.check("and shows the same translation", H.status(PAGE_TRANSLATION) == "done" and translationText():find("[en] casa", 1, true) ~= nil, translationText())
		plugin:refreshTranslationWithTarget(plugin.current_state, "fr")
	end)
	H.step(1, function()
		H.check("another target language queries", H.calls.translation == 2 and translationText():find("[fr] casa", 1, true) ~= nil, H.calls.translation)
		plugin:refreshTranslationWithTarget(plugin.current_state, "en")
	end)
	H.step(1, function()
		H.check("going back to the first one does not", H.calls.translation == 2 and translationText():find("[en] casa", 1, true) ~= nil, H.calls.translation)
		H.closeCarousel()
	end)

	-- ---- trapper and cache: wikipedia ----------------------------------------
	wikipedia("house")
	H.step(1, function()
		H.check("the first Wikipedia search queries", H.calls.wikipedia == 1, H.calls.wikipedia)
		H.check("under Trapper:wrap", H.calls.wikipedia_wrapped == true)
		H.closeCarousel()
	end)
	wikipedia("house")
	H.step(1, function()
		H.check("searching it again needs no query", H.calls.wikipedia == 1 and H.status(PAGE_WIKIPEDIA) == "done", H.calls.wikipedia)
		plugin:refreshWikipediaWithLanguage(plugin.current_state, "pt")
	end)
	H.step(1, function()
		H.check("another Wikipedia language queries", H.calls.wikipedia == 2, H.calls.wikipedia)
		plugin:refreshWikipediaWithLanguage(plugin.current_state, "en")
	end)
	H.step(1, function()
		H.check("going back to the first one does not", H.calls.wikipedia == 2, H.calls.wikipedia)
		H.closeCarousel()
	end)

	-- ---- nothing found, and retry --------------------------------------------
	wikipedia("qqqzzzz")
	H.step(1, function()
		H.check("an article not found is empty", H.status(PAGE_WIKIPEDIA) == "empty" and H.calls.wikipedia == 3, H.calls.wikipedia)
		H.closeCarousel()
	end)
	wikipedia("qqqzzzz")
	H.step(1, function()
		H.check("and is cached too", H.status(PAGE_WIKIPEDIA) == "empty" and H.calls.wikipedia == 3, H.calls.wikipedia)
		local retry = H.findButton("Query Wikipedia")
		H.check("Retry is the retry.svg icon", retry and tostring(retry.icon_file):find("/icons/retry.svg", 1, true) ~= nil, retry and tostring(retry.icon_file))
		H.check("Retry is offered and tapped", H.tapButton("Query Wikipedia"))
	end)
	H.step(1, function()
		H.check("Retry searches again", H.calls.wikipedia == 4, H.calls.wikipedia)
		H.closeCarousel()
	end)

	-- ---- errors --------------------------------------------------------------
	H.step(0.3, function()
		fail_translation = "connection refused"
	end)
	translate("house")
	H.step(1, function()
		local status, message = H.status(PAGE_TRANSLATION)
		H.check("a failed translation is an error", status == "error" and H.calls.translation == 3, tostring(status) .. " " .. tostring(message))
		H.closeCarousel()
		fail_translation = nil
	end)
	translate("house")
	H.step(1, function()
		H.check("and is not cached: the next lookup queries again", H.status(PAGE_TRANSLATION) == "done" and H.calls.translation == 4, H.calls.translation)
		H.closeCarousel()
	end)

	-- ---- interrupted ---------------------------------------------------------
	H.step(0.3, function()
		fail_wikipedia = "Interrupted by user"
	end)
	wikipedia("livro")
	H.step(1, function()
		local status, message = H.status(PAGE_WIKIPEDIA)
		H.check("a cancelled Wikipedia search says so", status == "error" and message == "Wikipedia lookup interrupted.", tostring(status) .. " " .. tostring(message))
		fail_wikipedia = nil
		H.check("with Retry", H.tapButton("Query Wikipedia"))
	end)
	H.step(1, function()
		H.check("which searches again", H.status(PAGE_WIKIPEDIA) == "done", H.status(PAGE_WIKIPEDIA))
		H.closeCarousel()
	end)

	-- ---- macos ---------------------------------------------------------------
	H.step(0.3, function()
		plugin.online_queries_in_subprocess = false
	end)
	translate("near")
	H.step(1, function()
		H.check("on macOS, a query runs in KOReader's process", H.calls.unwrapped == 1, H.calls.wrapped .. " wrapped, " .. H.calls.unwrapped .. " not")
		H.check("and answers", H.status(PAGE_TRANSLATION) == "done", H.status(PAGE_TRANSLATION))
		H.closeCarousel()
		plugin.online_queries_in_subprocess = true
	end)

	-- ---- manual --------------------------------------------------------------
	H.step(0.3, function()
		plugin:setOnlineCardLoadMode("manual_only")
	end)
	translate("casa")
	H.step(1, function()
		H.check("manual only: a cached translation is shown at once", H.status(PAGE_TRANSLATION) == "done", H.status(PAGE_TRANSLATION))
		H.check("with no query", H.calls.translation == 5, H.calls.translation)
		H.closeCarousel()
	end)
	translate("livro")
	H.step(1, function()
		local count = H.calls.translation
		H.check("anything else waits", H.status(PAGE_TRANSLATION) == "idle" and count == 5, H.status(PAGE_TRANSLATION) .. " " .. count)
		local load = H.findButton("Query the translation service")
		H.check("Load is the load_online.svg icon", load and tostring(load.icon_file):find("/icons/load_online.svg", 1, true) ~= nil, load and tostring(load.icon_file))
		H.check("for the Load button", H.tapButton("Query the translation service"))
	end)
	H.step(1, function()
		H.check("which queries", H.status(PAGE_TRANSLATION) == "done" and H.calls.translation == 6, H.calls.translation)
		H.closeCarousel()
		plugin:setOnlineCardLoadMode("automatic")
	end)

	H.finish()
end
