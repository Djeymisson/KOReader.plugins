-- KOReader's gettext catalog does not contain strings from external plugins.
-- Keep plugin-specific translations here and fall back to KOReader's catalog
-- for languages without a Reader Header/Footer translation (and for native
-- UI terms). Mirrors quickdock.koplugin/quickdock_l10n.lua.
local gettext = require("gettext")

local locale = type(gettext) == "table" and gettext.current_lang or nil
if not locale or locale == "C" then
    local settings = rawget(_G, "G_reader_settings")
    locale = settings and settings.readSetting and settings:readSetting("language") or locale
end
locale = tostring(locale or "C"):gsub("-", "_")
if not locale:match("^pt_BR") and not locale:match("^pt_PT") then
    return gettext
end

-- This plugin's vocabulary (font, margins, Wi-Fi, clock, pages) has no
-- wording differences between Brazilian and European Portuguese, unlike
-- quickdock's file-browser terms, so a single table serves both locales.
--
-- Only strings with no exact match in KOReader's own "koreader" textdomain
-- belong here — anything already translated by KOReader itself (checked
-- against the compiled l10n/pt_BR/koreader.mo and l10n/pt_PT/koreader.mo
-- catalogs) is deliberately left out and falls through to gettext(msgid)
-- below, so it picks up KOReader's own (and possibly per-region: e.g.
-- "Battery percentage" is "Porcentagem"/"Percentagem" depending on locale)
-- translation instead of a second, possibly drifting copy kept here.
local pt = {
    ["Reader Header Footer"] = "Reader Header Footer",
    ["Shows custom header and footer information on reader pages."] = "Mostra informações personalizadas de cabeçalho e rodapé nas páginas do leitor.",

    ["Header/footer indicators"] = "Indicadores de cabeçalho/rodapé",
    ["Show header/footer"] = "Mostrar cabeçalho/rodapé",
    ["Displayed items"] = "Itens exibidos",
    ["Wi-Fi status"] = "Status do Wi-Fi",
    ["Clock"] = "Relógio",
    ["Bottom-left pages left"] = "Páginas restantes (inferior esquerdo)",
    ["Reading percentage"] = "Porcentagem de leitura",
    ["Bottom-left info: pages left in book"] = "Informação inferior esquerda: páginas restantes no livro",
    ["Bottom-left info: pages left in chapter"] = "Informação inferior esquerda: páginas restantes no capítulo",

    ["Font size: %d"] = "Tamanho da fonte: %d",
    ["Header/footer font size"] = "Tamanho da fonte do cabeçalho/rodapé",
    ["Reset font size"] = "Redefinir tamanho da fonte",

    ["Margins"] = "Margens",
    ["Follow document margins"] = "Seguir margens do documento",
    ["Custom side margins: %d"] = "Margens laterais personalizadas: %d",
    ["Custom side indicator margins"] = "Margens laterais personalizadas dos indicadores",
    ["Custom left margin: %d"] = "Margem esquerda personalizada: %d",
    ["Custom left indicator margin"] = "Margem esquerda personalizada do indicador",
    ["Custom right margin: %d"] = "Margem direita personalizada: %d",
    ["Custom right indicator margin"] = "Margem direita personalizada do indicador",

    ["Version: %s"] = "Versão: %s",
    ["Reader Header/Footer\nVersion: %s"] = "Reader Header/Footer\nVersão: %s",
}

-- Plural pairs for the bottom-left "pages left" indicator, keyed by the
-- English singular|plural msgid pair used at the call site (T() templates,
-- %1 placeholder). ngettext() below only consults this for the two pairs
-- actually used by the plugin; anything else still goes through KOReader's
-- own gettext.ngettext.
local PLURALS = {
    ["%1 page left in book|%1 pages left in book"] = {
        "%1 página restante no livro",
        "%1 páginas restantes no livro",
    },
    ["%1 page left in chapter|%1 pages left in chapter"] = {
        "%1 página restante no capítulo",
        "%1 páginas restantes no capítulo",
    },
}

local function ngettext(msgid, msgid_plural, n)
    local forms = PLURALS[msgid .. "|" .. msgid_plural]
    if forms then
        return (n == 1) and forms[1] or forms[2]
    end
    return gettext.ngettext(msgid, msgid_plural, n)
end

return setmetatable({
    ngettext = ngettext,
    pgettext = gettext.pgettext,
}, {
    __call = function(_, msgid)
        return pt[msgid] or gettext(msgid)
    end,
})
