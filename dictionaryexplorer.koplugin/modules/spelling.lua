--[[
Spelling of words, apart from any dictionary: case and accents.

  foldAscii       A-Z to a-z only: what the StarDict sort order folds
  changeCase      lower or upper case for any letter ("Árvore" -> "árvore"),
                  through the utf8proc KOReader ships (A-Z only without it)
  caseVariants    the other casings a key may be stored under
  plainSpelling   lowercase and without accents ("Ação" -> "acao")
  accented        the accented forms of a plain letter ("a" -> á, à, â...)
  characters      a text split into its characters (UTF-8), not bytes

Plain Lua but for utf8proc, which it does without.
]]

local Spelling = {}

local ASCII_FOLD = {}
for code = string.byte("A"), string.byte("Z") do
	ASCII_FOLD[string.char(code)] = string.char(code + 32)
end

--- A-Z to a-z, and nothing else.
function Spelling.foldAscii(text)
	return (text:gsub("[A-Z]", ASCII_FOLD))
end

local Utf8Proc
do
	local ok, module = pcall(require, "ffi/utf8proc")
	Utf8Proc = ok and module or nil
end

--- `text` in lower (`lower` true) or upper case, for any letter.
function Spelling.changeCase(text, lower)
	if Utf8Proc then
		local ok, cased = pcall(Utf8Proc.cased_dumb, text, lower)
		if ok and cased then
			return cased
		end
	end
	return lower and Spelling.foldAscii(text) or text:upper()
end

--- The other casings a key may be stored under: all lowercase (a word at the
-- start of a sentence), capitalized (a name typed in lowercase) and all
-- uppercase (an abbreviation), each once and none the same as `word`.
function Spelling.caseVariants(word)
	local changeCase = Spelling.changeCase
	local lowered = changeCase(word, true)
	local first, rest = lowered:match("^([%z\1-\127\194-\244][\128-\191]*)(.*)$")
	local candidates = { lowered, first and (changeCase(first, false) .. rest), changeCase(word, false) }
	local variants, seen = {}, { [word] = true }
	for index = 1, 3 do
		local candidate = candidates[index]
		if candidate and not seen[candidate] then
			seen[candidate] = true
			variants[#variants + 1] = candidate
		end
	end
	return variants
end

-- The accented lowercase letters of the Latin-1 range, by their plain letter.
-- All are two bytes, the first one \195.
local ACCENTED = {
	a = { "á", "à", "â", "ã", "ä", "å" },
	e = { "é", "è", "ê", "ë" },
	i = { "í", "ì", "î", "ï" },
	o = { "ó", "ò", "ô", "õ", "ö" },
	u = { "ú", "ù", "û", "ü" },
	c = { "ç" },
	n = { "ñ" },
	y = { "ý", "ÿ" },
}
local PLAIN = {}
for plain, accented in pairs(ACCENTED) do
	for _index, letter in ipairs(accented) do
		PLAIN[letter] = plain
	end
end
local NONE = {}

--- The accented forms of a plain lowercase letter (an empty list for others).
function Spelling.accented(letter)
	return ACCENTED[letter] or NONE
end

--- The word without its accents, in lowercase ("Ação" -> "acao").
function Spelling.plainSpelling(word)
	return (Spelling.changeCase(word, true):gsub("\195[\128-\191]", function(letter)
		return PLAIN[letter] or letter
	end))
end

--- `text` split into its characters (UTF-8 sequences), not bytes.
function Spelling.characters(text)
	local characters = {}
	for character in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		characters[#characters + 1] = character
	end
	return characters
end

return Spelling
