-- Tests of modules/text.lua, which is plain Lua and needs no
-- KOReader. Run with run.sh (unit), or:
--   DE_PLUGIN=/path/to/dictionaryexplorer.koplugin luajit text_test.lua

local plugin = assert(os.getenv("DE_PLUGIN"), "set DE_PLUGIN to the plugin folder")
local Text = dofile(plugin .. "/modules/text.lua")

local passed, failed = 0, 0
local function check(name, ok, detail)
	if ok then
		passed = passed + 1
	else
		failed = failed + 1
	end
	print(string.format("%s  %s%s", ok and "PASS" or "FAIL", name, detail and (" -- " .. detail) or ""))
end
local function equal(name, got, expected)
	check(name, got == expected, got ~= expected and string.format("got %q, expected %q", got, expected) or nil)
end

-- ---- "m": must behave exactly as it always has --------------------------------
-- The implementation before the "x" support, kept here as the reference.
local KEPT_TAGS = { b = true, i = true, u = true, em = true, strong = true, small = true, big = true, sup = true, sub = true }
local function reference(definition)
	local html = definition:gsub("<[bB][rR] ?/?>", "\n")
	html = html:gsub("<(/?)(%a+)[^>]*>", function(slash, tag)
		tag = tag:lower()
		if KEPT_TAGS[tag] then
			return "<" .. slash .. tag .. ">"
		end
		return ""
	end)
	html = html:gsub("^%s+", ""):gsub("\n", "<br/>")
	return html
end

-- Real entries (Priberam Portuguese) and a fuzz of tag soup, whitespace and line breaks.
local real = {
	"<b><big>casa</big></b> <i>s. f.</i> <b>1.</b>\194\160Nome gen\195\169rico de todas as constru\195\167\195\181es. <b>2.</b>\194\160Constru\195\167\195\163o. = <small>MORADIA, VIVENDA</small>",
	'<b><big>casar</big></b> <i>v. tr.</i> <small><font color="#555555">[Brasil]</font></small> Fazer uma aposta. <br/> \226\128\162 x<sup>2</sup>',
	"  leading spaces\n\nand two lines <BR> upper-case break <Br />",
}
local identical = true
for _index, definition in ipairs(real) do
	identical = identical and Text.plainToHtml(definition) == reference(definition)
end
check('"m" gives the same HTML as before on real entries', identical)

math.randomseed(11)
local pieces = { "<b>", "</b>", "<i>", "</i>", "<font color=\"red\">", "</font>", "<br>", "<BR/>", "\n", "\n\n", " ", "\t", "word", "\226\128\162", "<sup>", "</sup>", "<k>", "<def>", "&amp;" }
local fuzz_identical = true
for _trial = 1, 500 do
	local parts = {}
	for _piece = 1, math.random(1, 25) do
		parts[#parts + 1] = pieces[math.random(#pieces)]
	end
	local definition = table.concat(parts)
	fuzz_identical = fuzz_identical and Text.plainToHtml(definition) == reference(definition)
end
check('"m" gives the same HTML as before on 500 random mixes of tags and whitespace', fuzz_identical)

-- ---- "x" ---------------------------------------------------------------------
-- The Portuguese-English dictionary: <k>key</k>, then the translations.
equal(
	"x: <k> becomes the bold headword, blank lines between translations are dropped",
	Text.xdxfLiteToHtml("<k>casa</k>\nhouse, house-\n\nhouse-\n\nhouse", "casa"),
	"<b>casa</b><br/>house, house-<br/>house-<br/>house"
)
equal("x: a one-line entry", Text.xdxfLiteToHtml("<k>gripe, aperto</k>\ngrip", "gripe, aperto"), "<b>gripe, aperto</b><br/>grip")

-- The Dicionário Aberto: the key, then the bold key, then the class on its own line.
equal(
	"x: the key repeated as the first line is dropped, and the headword joins its word class",
	Text.xdxfLiteToHtml("casa\n\t<b>casa</b>\n\t<i>f.</i>\n\tEdif\195\173cio para habita\195\167\195\163o: <i>uma casa moderna</i>.\n\tMorada.\n\n\n", "casa"),
	"<b>casa</b> <i>f.</i><br/>Edif\195\173cio para habita\195\167\195\163o: <i>uma casa moderna</i>.<br/>Morada."
)
equal(
	"x: the indentation of every line goes",
	Text.xdxfLiteToHtml("docel\n\t<b>docel</b>\n\t<i>m.</i>\n\t   F\195\179rma usual\n\t\t(V. <i>dossel</i>)", "docel"),
	"<b>docel</b> <i>m.</i><br/>F\195\179rma usual<br/>(V. <i>dossel</i>)"
)

-- Things that must be left alone.
equal("x: a first line that is not the key stays", Text.xdxfLiteToHtml("other\n<b>casa</b>\n<i>f.</i>", "casa"), "other<br/><b>casa</b> <i>f.</i>")
equal("x: a bold line followed by text is not merged", Text.xdxfLiteToHtml("<b>casa</b>\nplain", "casa"), "<b>casa</b><br/>plain")
equal("x: an italic line alone is not merged with the next one", Text.xdxfLiteToHtml("<i>f.</i>\n<b>x</b>", "z"), "<i>f.</i><br/><b>x</b>")
equal("x: a key that only differs in case is not treated as a repeat", Text.xdxfLiteToHtml("Casa\n<b>casa</b>", "casa"), "Casa<br/><b>casa</b>")

-- Line endings and unknown markup.
equal("x: Windows line endings", Text.xdxfLiteToHtml("<k>a</k>\r\none\r\n\r\ntwo\r\n", "a"), "<b>a</b><br/>one<br/>two")
equal("x: <br> counts as a line break", Text.xdxfLiteToHtml("<k>a</k><br>one<br/>two", "a"), "<b>a</b><br/>one<br/>two")
equal("x: structured XDXF tags are dropped, their text kept", Text.xdxfLiteToHtml("<k>a</k>\n<def><gr>n.</gr> thing</def>", "a"), "<b>a</b><br/>n. thing")
equal("x: entities are left for the HTML engine", Text.xdxfLiteToHtml("<k>a</k>\nit&apos;s", "a"), "<b>a</b><br/>it&apos;s")
equal("x: an empty definition gives nothing", Text.xdxfLiteToHtml("\n\n \t \n", "a"), "")

print(string.format("\nRESULT passed=%d failed=%d", passed, failed))
os.exit(failed == 0 and 0 or 1)
