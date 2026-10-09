-- The IconWidget patch that lets buttons use this plugin's own SVG files.

local IconWidget = require("ui/widget/iconwidget")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local C = ...

local PageAnchor = {}

-- Existence per path, looked up once: the patched init runs for every
-- IconWidget KOReader creates while a book is open, and the pill is
-- rebuilt on state changes, so it shouldn't stat the same files each time.
local is_file = {}
local function fileExists(path)
	local exists = is_file[path]
	if exists == nil then
		exists = lfs.attributes(path, "mode") == "file"
		is_file[path] = exists
	end
	return exists
end

-- Reuses Quick Dock's own trick: IconWidget only resolves bare icon names
-- against KOReader's system icon directories, so Button (which always
-- builds its icon through IconWidget) can't show this plugin's own SVGs on
-- its own. This patch teaches IconWidget to recognize a full, existing file
-- path passed as `icon` and use it directly, without touching the
-- name-resolution path every other caller in KOReader still relies on.
-- Namespaced separately from Quick Dock's own copy of this patch (distinct
-- fields on IconWidget), so the two coexist safely if both plugins are
-- installed. Only paths inside this plugin's own icons folder are handled
-- (a plain prefix check), so every other IconWidget goes straight through.
function PageAnchor:patchIconWidget()
	if self._pageanchor_icon_patch_active then
		return
	end
	self._pageanchor_icon_patch_active = true
	IconWidget._pageanchor_patch_users = (IconWidget._pageanchor_patch_users or 0) + 1

	if IconWidget._pageanchor_original_init then
		return
	end

	local original_init = IconWidget.init
	IconWidget._pageanchor_original_init = original_init

	local icons_dir = C.ICONS_DIR
	local prefix_len = #icons_dir
	local patched_init = function(icon_widget)
		local explicit_icon = rawget(icon_widget, "icon")
		if type(explicit_icon) == "string" and explicit_icon:sub(1, prefix_len) == icons_dir
				and fileExists(explicit_icon) then
			icon_widget.file = explicit_icon
		end
		return original_init(icon_widget)
	end

	IconWidget._pageanchor_patched_init = patched_init
	IconWidget.init = patched_init
end

function PageAnchor:unpatchIconWidget()
	if not self._pageanchor_icon_patch_active then
		return
	end
	self._pageanchor_icon_patch_active = nil
	IconWidget._pageanchor_patch_users = math.max(0, (IconWidget._pageanchor_patch_users or 1) - 1)
	if IconWidget._pageanchor_patch_users > 0 then
		return
	end

	if IconWidget.init ~= IconWidget._pageanchor_patched_init then
		-- Something else replaced IconWidget.init after we patched it (a
		-- future KOReader version touching the same hook, or another patch
		-- layered on top without chaining back to ours). Restoring blindly
		-- here could drop that other patch, so leave it alone and just log --
		-- a starting point if plugin icons ever start misbehaving.
		logger.warn("PageAnchor: IconWidget.init changed unexpectedly during unpatch; leaving it as-is")
		IconWidget._pageanchor_patch_users = nil
		return
	end

	IconWidget.init = IconWidget._pageanchor_original_init
	IconWidget._pageanchor_original_init = nil
	IconWidget._pageanchor_patched_init = nil
	IconWidget._pageanchor_patch_users = nil
end

return PageAnchor
