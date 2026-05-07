local Device = require("device")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local Size = require("ui/size")
local Screen = Device.screen
local Blitbuffer = require("ffi/blitbuffer")
local _ = require("gettext")
local UIManager = require("ui/uimanager")
local NetworkMgr = require("ui/network/manager")
local SpinWidget = require("ui/widget/spinwidget")
local logger = require("logger")

local ReaderHeaderFooter = WidgetContainer:extend({
	name = "reader_header_footer",
	is_doc_only = true,

	enabled_setting_key = "reader_header_footer_enabled",
	enabled = true,

	font_size_default = 16,
	font_size_min = 10,
	font_size_max = 28,
	font_size_setting_key = "reader_header_footer_font_size",

	font_size = 16,
	padding = 10,

	refresh_region_font_size = 16,

	menu_registered = false,

	clock_refresh_fn = nil,

	battery_check_fn = nil,
	battery_check_interval = 300,

	last_wifi_on = nil,
	last_battery_level = nil,
	last_charging = nil,

	top_refresh_pending = false,
	bottom_refresh_pending = false,

	deferred_top_refresh = false,
	deferred_bottom_refresh = false,
	deferred_refresh_fn = nil,

	pageno = nil,
	pages = nil,
})

local function safe_call(fn, fallback)
	local ok, result = pcall(fn)
	if ok and result ~= nil then
		return result
	end
	return fallback
end

function ReaderHeaderFooter:registerMenu()
	if self.menu_registered then
		logger.info("reader_header_footer: menu already registered")
		return
	end

	if self.ui and self.ui.menu and self.ui.menu.registerToMainMenu then
		logger.info("reader_header_footer: registering menu")
		self.ui.menu:registerToMainMenu(self)
		self.menu_registered = true
	else
		logger.warn("reader_header_footer: reader menu not available yet")
	end
end

function ReaderHeaderFooter:normalizeFontSize(value)
	value = tonumber(value) or self.font_size_default
	value = math.floor(value)

	if value < self.font_size_min then
		value = self.font_size_min
	elseif value > self.font_size_max then
		value = self.font_size_max
	end

	return value
end

function ReaderHeaderFooter:loadSettings()
	local saved_enabled = G_reader_settings:readSetting(self.enabled_setting_key)

	if saved_enabled == nil then
		self.enabled = true
	else
		self.enabled = saved_enabled
	end

	local saved_font_size = G_reader_settings:readSetting(self.font_size_setting_key)
	self.font_size = self:normalizeFontSize(saved_font_size or self.font_size_default)
	self.refresh_region_font_size = self.font_size
end

function ReaderHeaderFooter:setFontSize(font_size)
	local old_font_size = self.font_size
	local new_font_size = self:normalizeFontSize(font_size)

	if old_font_size == new_font_size then
		return
	end

	self.font_size = new_font_size
	self.refresh_region_font_size = math.max(old_font_size, new_font_size)

	G_reader_settings:saveSetting(self.font_size_setting_key, new_font_size)

	self.font_face = Font:getFace("NotoSans-Regular.ttf", self.font_size)
end

function ReaderHeaderFooter:resetFontSize()
	self:setFontSize(self.font_size_default)
	G_reader_settings:delSetting(self.font_size_setting_key)
end

function ReaderHeaderFooter:isEnabled()
	return self.enabled ~= false
end

function ReaderHeaderFooter:setEnabled(enabled)
	local old_enabled = self:isEnabled()
	self.enabled = enabled == true

	G_reader_settings:saveSetting(self.enabled_setting_key, self.enabled)

	if self.enabled then
		self:rememberCurrentIndicatorState()
		self:startClockWatcher()
		self:startBatteryWatcher()
	else
		self:stopClockWatcher()
		self:stopBatteryWatcher()
		self:stopDeferredRefreshCheck()
	end

	-- Se estava ativado e foi desativado, isso limpa as áreas onde
	-- os indicadores estavam desenhados. Se foi ativado, desenha de novo.
	if old_enabled ~= self.enabled then
		UIManager:scheduleIn(0.1, function()
			self:requestAllIndicatorRefresh()
		end)
	end
end

function ReaderHeaderFooter:toggleEnabled()
	self:setEnabled(not self:isEnabled())
end

function ReaderHeaderFooter:addToMainMenu(menu_items)
	menu_items.reader_header_footer = {
		text = _("Header/footer indicators"),
		sorting_hint = "setting",
		sub_item_table = {
			{
				text_func = function()
					if self:isEnabled() then
						return _("Disable plugin")
					else
						return _("Enable plugin")
					end
				end,

				checked_func = function()
					return self:isEnabled()
				end,

				callback = function(touchmenu_instance)
					self:toggleEnabled()

					if touchmenu_instance and touchmenu_instance.updateItems then
						touchmenu_instance:updateItems()
					end
				end,
			},

			{
				text_func = function()
					return string.format(_("Font size: %d"), self.font_size)
				end,

				enabled_func = function()
					return self:isEnabled()
				end,

				callback = function(touchmenu_instance)
					if not self:isEnabled() then
						return
					end

					local widget = SpinWidget:new({
						title_text = _("Header/footer font size"),
						value = self.font_size,
						value_min = self.font_size_min,
						value_max = self.font_size_max,
						default_value = self.font_size_default,
						keep_shown_on_apply = false,

						callback = function(spin)
							self:setFontSize(spin.value)

							if touchmenu_instance and touchmenu_instance.updateItems then
								touchmenu_instance:updateItems()
							end

							UIManager:scheduleIn(0.1, function()
								self:requestAllIndicatorRefresh()
							end)
						end,
					})

					UIManager:show(widget)
				end,
			},

			{
				text = _("Reset font size"),
				
				enabled_func = function()
					return self:isEnabled()
				end,

				callback = function(touchmenu_instance)
					self:resetFontSize()

					if touchmenu_instance and touchmenu_instance.updateItems then
						touchmenu_instance:updateItems()
					end

					UIManager:scheduleIn(0.1, function()
						self:requestAllIndicatorRefresh()
					end)
				end,
			},
		},
	}
end

function ReaderHeaderFooter:deferIndicatorRefresh(which)
	if which == "top" then
		self.deferred_top_refresh = true
	elseif which == "bottom" then
		self.deferred_bottom_refresh = true
	elseif which == "all" then
		self.deferred_top_refresh = true
		self.deferred_bottom_refresh = true
	end

	self:scheduleDeferredRefreshCheck()
end

function ReaderHeaderFooter:scheduleDeferredRefreshCheck()
	if self.deferred_refresh_fn then
		return
	end

	self.deferred_refresh_fn = function()
		self.deferred_refresh_fn = nil

		if not self.ui or not self.ui.document then
			self.deferred_top_refresh = false
			self.deferred_bottom_refresh = false
			return
		end

		-- Ainda tem menu/dialog por cima: não redesenha nada.
		if not self:isReaderWindowOnTop() then
			self:scheduleDeferredRefreshCheck()
			return
		end

		local refresh_top = self.deferred_top_refresh
		local refresh_bottom = self.deferred_bottom_refresh

		self.deferred_top_refresh = false
		self.deferred_bottom_refresh = false

		if refresh_top then
			self:requestTopIndicatorRefresh()
		end

		if refresh_bottom then
			self:requestBottomIndicatorRefresh()
		end
	end

	-- Intervalo curto, mas sem repaint.
	-- Ele apenas verifica se o menu já saiu.
	UIManager:scheduleIn(0.5, self.deferred_refresh_fn)
end

function ReaderHeaderFooter:stopDeferredRefreshCheck()
	if self.deferred_refresh_fn then
		UIManager:unschedule(self.deferred_refresh_fn)
		self.deferred_refresh_fn = nil
	end

	self.deferred_top_refresh = false
	self.deferred_bottom_refresh = false
end

function ReaderHeaderFooter:getReaderWindowWidget()
	if self.ui and self.ui.view and self.ui.view.dialog then
		return self.ui.view.dialog
	end

	return nil
end

function ReaderHeaderFooter:isReaderWindowOnTop()
	local reader_widget = self:getReaderWindowWidget()

	if not reader_widget then
		return false
	end

	local top_widget = UIManager:getTopmostVisibleWidget()

	return top_widget == reader_widget
end

function ReaderHeaderFooter:requestTopIndicatorRefresh()
	if self.top_refresh_pending then
		return
	end

	self.top_refresh_pending = true

	UIManager:nextTick(function()
		self.top_refresh_pending = false

		if not self.ui or not self.ui.view or not self.ui.view.dialog then
			return
		end

		-- Se existe menu/dialog por cima, não atualiza agora.
		if not self:isReaderWindowOnTop() then
			self:deferIndicatorRefresh("top")
			return
		end

		local top_region = self:getIndicatorRefreshRegions()

		-- Use "ui", não "partial", porque isso é overlay de interface.
		UIManager:setDirty(self.ui.view.dialog, "ui", top_region)
	end)
end

function ReaderHeaderFooter:requestBottomIndicatorRefresh()
	if self.bottom_refresh_pending then
		return
	end

	self.bottom_refresh_pending = true

	UIManager:nextTick(function()
		self.bottom_refresh_pending = false

		if not self.ui or not self.ui.view or not self.ui.view.dialog then
			return
		end

		-- Se existe menu/dialog por cima, não atualiza agora.
		if not self:isReaderWindowOnTop() then
			self:deferIndicatorRefresh("bottom")
			return
		end

		local _, bottom_region = self:getIndicatorRefreshRegions()

		UIManager:setDirty(self.ui.view.dialog, "ui", bottom_region)
	end)
end

function ReaderHeaderFooter:requestAllIndicatorRefresh()
	self:requestTopIndicatorRefresh()
	self:requestBottomIndicatorRefresh()
end

function ReaderHeaderFooter:requestIndicatorRefresh()
	if self.refresh_pending then
		return
	end

	self.refresh_pending = true

	UIManager:nextTick(function()
		self.refresh_pending = false

		if not self.ui or not self.ui.view or not self.ui.view.dialog then
			return
		end

		local top_region, bottom_region = self:getIndicatorRefreshRegions()

		UIManager:setDirty(self.ui.view.dialog, "partial", top_region)
		UIManager:setDirty(self.ui.view.dialog, "partial", bottom_region)
	end)
end

function ReaderHeaderFooter:getIndicatorRefreshRegions()
	local screen_w = Screen:getWidth()
	local screen_h = Screen:getHeight()

	local pad = Screen:scaleBySize(self.padding)

	local region_font_size = self.refresh_region_font_size or self.font_size
	local line_h = Screen:scaleBySize(region_font_size + 8)

	local left_bound, right_bound = self:getContentHorizontalBounds()

	-- Um pequeno respiro para apagar texto antigo quando mudar de tamanho.
	local extra = Screen:scaleBySize(6)

	-- Faixa superior: cobre topo esquerdo e topo direito.
	local top_region = Geom:new({
		x = math.max(0, left_bound - extra),
		y = math.max(0, pad - extra),
		w = math.min(screen_w, right_bound - left_bound + extra * 2),
		h = line_h + extra * 2,
	})

	-- Faixa inferior: cobre rodapé esquerdo e rodapé direito.
	local bottom_region = Geom:new({
		x = math.max(0, left_bound - extra),
		y = math.max(0, screen_h - line_h - pad - extra),
		w = math.min(screen_w, right_bound - left_bound + extra * 2),
		h = line_h + extra * 2,
	})

	return top_region, bottom_region
end

function ReaderHeaderFooter:getWifiState()
	return safe_call(function()
		return NetworkMgr:isWifiOn()
	end, false)
end

function ReaderHeaderFooter:getPowerSnapshot()
	if not Device:hasBattery() then
		return {
			level = nil,
			charging = false,
		}
	end

	local powerd = Device:getPowerDevice()
	if not powerd then
		return {
			level = nil,
			charging = false,
		}
	end

	local level = safe_call(function()
		return powerd:getCapacity()
	end, nil)

	local charging = safe_call(function()
		return powerd:isCharging()
	end, false)

	return {
		level = level,
		charging = charging,
	}
end

function ReaderHeaderFooter:rememberCurrentIndicatorState()
	local power = self:getPowerSnapshot()

	self.last_wifi_on = self:getWifiState()
	self.last_battery_level = power.level
	self.last_charging = power.charging
end

function ReaderHeaderFooter:startClockWatcher()
	if self.clock_refresh_fn then
		return
	end

	self.clock_refresh_fn = function()
		self.clock_refresh_fn = nil

		if not self.ui or not self.ui.document then
			return
		end

		self:requestTopIndicatorRefresh()
		self:startClockWatcher()
	end

	local seconds_now = tonumber(os.date("%S")) or 0
	local delay = 60 - seconds_now

	if delay <= 0 then
		delay = 60
	end

	UIManager:scheduleIn(delay, self.clock_refresh_fn)
end

function ReaderHeaderFooter:stopClockWatcher()
	if self.clock_refresh_fn then
		UIManager:unschedule(self.clock_refresh_fn)
		self.clock_refresh_fn = nil
	end
end

function ReaderHeaderFooter:onNetworkConnected()
	if not self:isEnabled() then
		return
	end
	local wifi_on = self:getWifiState()

	if wifi_on ~= self.last_wifi_on then
		self.last_wifi_on = wifi_on
		self:requestTopIndicatorRefresh()
	end
end

function ReaderHeaderFooter:onNetworkDisconnected()
	if not self:isEnabled() then
		return
	end
	local wifi_on = self:getWifiState()

	if wifi_on ~= self.last_wifi_on then
		self.last_wifi_on = wifi_on
		self:requestTopIndicatorRefresh()
	end
end

function ReaderHeaderFooter:onCharging()
	if not self:isEnabled() then
		return
	end
	local power = self:getPowerSnapshot()

	self.last_battery_level = power.level
	self.last_charging = power.charging

	self:requestTopIndicatorRefresh()
end

function ReaderHeaderFooter:onNotCharging()
	if not self:isEnabled() then
		return
	end
	local power = self:getPowerSnapshot()

	self.last_battery_level = power.level
	self.last_charging = power.charging

	self:requestTopIndicatorRefresh()
end

function ReaderHeaderFooter:startBatteryWatcher()
	if self.battery_check_fn then
		return
	end

	self.battery_check_fn = function()
		self.battery_check_fn = nil

		if not self.ui or not self.ui.document then
			return
		end

		local power = self:getPowerSnapshot()

		if power.level ~= self.last_battery_level or power.charging ~= self.last_charging then
			self.last_battery_level = power.level
			self.last_charging = power.charging

			self:requestTopIndicatorRefresh()
		end

		self:startBatteryWatcher()
	end

	UIManager:scheduleIn(self.battery_check_interval, self.battery_check_fn)
end

function ReaderHeaderFooter:stopBatteryWatcher()
	if self.battery_check_fn then
		UIManager:unschedule(self.battery_check_fn)
		self.battery_check_fn = nil
	end
end

function ReaderHeaderFooter:onViewRecalculate(visible_area, page_area)
	self.visible_area = visible_area and visible_area:copy() or nil
	self.page_area = page_area and page_area:copy() or nil
end

function ReaderHeaderFooter:getContentHorizontalBounds()
	local screen_w = Screen:getWidth()
	local pad = Screen:scaleBySize(self.padding)

	local left_x = pad
	local right_x = screen_w - pad

	local offset_x = 0
	if self.ui and self.ui.view and self.ui.view.state and self.ui.view.state.offset then
		offset_x = self.ui.view.state.offset.x or 0
	end

	-- 1) Melhor caso: usar margens reais do documento
	if self.ui and self.ui.document and self.ui.document.getPageMargins then
		local ok, margins = pcall(function()
			return self.ui.document:getPageMargins()
		end)

		if ok and type(margins) == "table" then
			local left_margin = margins.left or 0
			local right_margin = margins.right or 0

			left_x = math.max(left_x, offset_x + left_margin)
			right_x = math.min(right_x, screen_w - offset_x - right_margin)
		end
	end

	-- 2) Refino/fallback: limitar também pela visible_area
	if self.visible_area then
		left_x = math.max(left_x, self.visible_area.x + pad)
		right_x = math.min(right_x, self.visible_area.x + self.visible_area.w - pad)
	end

	-- Segurança
	if right_x <= left_x then
		left_x = pad
		right_x = screen_w - pad
	end

	return left_x, right_x
end

function ReaderHeaderFooter:fitTextToWidth(text, max_width)
	if not text or text == "" then
		return ""
	end

	if self:getTextSize(text).w <= max_width then
		return text
	end

	local ellipsis = "..."
	local fitted = text

	while #fitted > 1 and self:getTextSize(fitted .. ellipsis).w > max_width do
		fitted = fitted:sub(1, -2)
	end

	return fitted .. ellipsis
end

function ReaderHeaderFooter:init()
	self:loadSettings()

	self.font_face = Font:getFace("NotoSans-Regular.ttf", self.font_size)

	-- Em plugins de leitura, self.ui costuma estar disponível.
	-- Registramos este plugin como um módulo visual da página.
	if self.ui and self.ui.view and self.ui.view.registerViewModule then
		self.ui.view:registerViewModule(self.name, self)
	end

	-- Registra o menu de configurações no menu do leitor.
	self:registerMenu()
end

function ReaderHeaderFooter:onReaderReady()
	self:registerMenu()

	if self.ui and self.ui.document then
		self.pages = safe_call(function()
			return self.ui.document:getPageCount()
		end, nil)
	end

	if self.ui and self.ui.view and self.ui.view.state then
		self.pageno = self.ui.view.state.page
	end

	self:rememberCurrentIndicatorState()

	if self:isEnabled() then
		self:startClockWatcher()
		self:startBatteryWatcher()
	end
end

function ReaderHeaderFooter:onPageUpdate(pageno)
	self.pageno = pageno
	if not self:isEnabled() then
		return
	end
	self:requestAllIndicatorRefresh()
end

function ReaderHeaderFooter:onPosUpdate(_, pageno)
	if pageno then
		self.pageno = pageno
		if not self:isEnabled() then
			return
		end
		self:requestAllIndicatorRefresh()
	end
end

function ReaderHeaderFooter:onSetDimensions()
	-- Nada obrigatório aqui, mas manter o handler ajuda em rotação/redimensionamento.
end

function ReaderHeaderFooter:getCurrentPage()
	if self.pageno then
		return self.pageno
	end

	if self.ui and self.ui.view and self.ui.view.state then
		return self.ui.view.state.page
	end

	if self.ui and self.ui.document then
		return safe_call(function()
			return self.ui.document:getCurrentPage()
		end, 1)
	end

	return 1
end

function ReaderHeaderFooter:getPageCount()
	if self.pages then
		return self.pages
	end

	if self.ui and self.ui.document then
		self.pages = safe_call(function()
			return self.ui.document:getPageCount()
		end, nil)
	end

	return self.pages
end

function ReaderHeaderFooter:getWifiText()
	local NetworkMgr = require("ui/network/manager")

	local wifi_on = safe_call(function()
		return NetworkMgr:isWifiOn()
	end, false)

	-- Ícones usados pelo próprio KOReader no footer.
	-- Se sua fonte não renderizar, troque por "WiFi" e "WiFi off".
	return wifi_on and "" or ""
end

function ReaderHeaderFooter:getBatteryText()
	if not Device:hasBattery() then
		return ""
	end

	local powerd = Device:getPowerDevice()
	if not powerd then
		return ""
	end

	local level = safe_call(function()
		return powerd:getCapacity()
	end, nil)

	if not level then
		return ""
	end

	local charging = safe_call(function()
		return powerd:isCharging()
	end, false)

	local charged = safe_call(function()
		return powerd:isCharged()
	end, false)

	local icon = safe_call(function()
		return powerd:getBatterySymbol(charged, charging, level)
	end, "")

	return string.format("%s %d%%", icon, level)
end

function ReaderHeaderFooter:getRightTopStatus()
	local wifi_on = self:getWifiState()
	local wifi_icon = wifi_on and " • " or ""

	local time = os.date("%H:%M")
	local battery = self:getBatteryText()

	if battery == "" then
		return string.format("%s%s", wifi_icon, time)
	end

	return string.format("%s%s • %s", wifi_icon, time, battery)
end

function ReaderHeaderFooter:getTitle()
	if self.ui and self.ui.doc_props then
		return self.ui.doc_props.display_title or self.ui.doc_props.title or _("Document")
	end

	return _("Document")
end

function ReaderHeaderFooter:getAuthor()
	if self.ui and self.ui.doc_props then
		return self.ui.doc_props.authors or self.ui.doc_props.author or _("Unknown")
	end

	return _("Unknown")
end

function ReaderHeaderFooter:getChapterTitle(pageno)
	if not self.ui or not self.ui.toc then
		return ""
	end

	return safe_call(function()
		return self.ui.toc:getTocTitleByPage(pageno)
	end, "") or ""
end

function ReaderHeaderFooter:isChapterStart(pageno)
	if not self.ui or not self.ui.toc or not pageno then
		return false
	end

	-- Melhor caso: KOReader informa quantas páginas já foram lidas no capítulo.
	local pages_done = safe_call(function()
		return self.ui.toc:getChapterPagesDone(pageno)
	end, nil)

	if pages_done ~= nil then
		return pages_done == 0
	end

	-- Fallback: se o título do capítulo mudou em relação à página anterior.
	if pageno > 1 then
		local current = self:getChapterTitle(pageno)
		local previous = self:getChapterTitle(pageno - 1)
		return current ~= "" and current ~= previous
	end

	return true
end

function ReaderHeaderFooter:getLeftTopStatus()
	local pageno = self:getCurrentPage()

	if self:isChapterStart(pageno) then
		return ""
	end

	if pageno % 2 == 0 then
		return string.format("%s • %s", self:getAuthor(), self:getTitle())
	end

	return self:getChapterTitle(pageno)
end

function ReaderHeaderFooter:getPagesLeftInChapter()
	local pageno = self:getCurrentPage()

	if self.ui and self.ui.toc then
		local left = safe_call(function()
			return self.ui.toc:getChapterPagesLeft(pageno)
		end, nil)

		if left ~= nil then
			return left
		end
	end

	if self.ui and self.ui.document then
		return safe_call(function()
			return self.ui.document:getTotalPagesLeft(pageno)
		end, 0)
	end

	return 0
end

function ReaderHeaderFooter:getPercentageRead()
	local pageno = self:getCurrentPage()
	local pages = self:getPageCount()

	if pages and pages > 0 then
		return math.min(100, math.max(0, (pageno / pages) * 100))
	end

	return 0
end

function ReaderHeaderFooter:getTextSize(text)
	local widget = require("ui/widget/textwidget"):new({
		text = text,
		face = self.font_face,
	})

	local size = widget:getSize()
	widget:free()

	return size
end

function ReaderHeaderFooter:drawText(bb, x, y, text)
	if not text or text == "" then
		return
	end

	local TextWidget = require("ui/widget/textwidget")

	local widget = TextWidget:new({
		text = text,
		face = self.font_face,
	})

	widget:paintTo(bb, x, y)
	widget:free()
end

function ReaderHeaderFooter:paintTo(bb, x, y)
	if not self:isEnabled() then
		return
	end

	if not self.ui or not self.ui.document then
		return
	end

	local screen_w = Screen:getWidth()
	local screen_h = Screen:getHeight()

	local pad = Screen:scaleBySize(self.padding)
	local line_h = Screen:scaleBySize(self.font_size + 4)

	local left_bound, right_bound = self:getContentHorizontalBounds()
	local usable_w = right_bound - left_bound

	local function clearBehind(tx, ty, tw)
		bb:paintRect(tx - 2, ty - 1, tw + 4, line_h + 2, Blitbuffer.COLOR_WHITE)
	end

	-- =========================
	-- Superior direito
	-- =========================
	local rt_text = self:getRightTopStatus()
	local rt_size = self:getTextSize(rt_text)
	local rt_x = right_bound - rt_size.w
	local rt_y = pad

	clearBehind(rt_x, rt_y, rt_size.w)
	self:drawText(bb, rt_x, rt_y, rt_text)

	-- =========================
	-- Superior esquerdo
	-- =========================
	local lt_text = self:getLeftTopStatus()
	if lt_text ~= "" then
		-- Reserva espaço para não colidir com o bloco da direita
		local gap = Screen:scaleBySize(16)
		local max_left_w = math.max(40, usable_w - rt_size.w - gap)

		lt_text = self:fitTextToWidth(lt_text, max_left_w)
		local lt_size = self:getTextSize(lt_text)

		local lt_x = left_bound
		local lt_y = pad

		clearBehind(lt_x, lt_y, lt_size.w)
		self:drawText(bb, lt_x, lt_y, lt_text)
	end

	-- =========================
	-- Inferior esquerdo
	-- =========================
	local pages_left = self:getPagesLeftInChapter()
	local lb_text = string.format("%d pages left in chapter", pages_left)
	lb_text = self:fitTextToWidth(lb_text, math.floor(usable_w * 0.6))

	local lb_size = self:getTextSize(lb_text)
	local lb_x = left_bound
	local lb_y = screen_h - line_h - pad

	clearBehind(lb_x, lb_y, lb_size.w)
	self:drawText(bb, lb_x, lb_y, lb_text)

	-- =========================
	-- Inferior direito
	-- =========================
	local rb_text = string.format("%.1f%%", self:getPercentageRead())
	local rb_size = self:getTextSize(rb_text)
	local rb_x = right_bound - rb_size.w
	local rb_y = screen_h - line_h - pad

	clearBehind(rb_x, rb_y, rb_size.w)
	self:drawText(bb, rb_x, rb_y, rb_text)
end

function ReaderHeaderFooter:onCloseDocument()
	self:stopClockWatcher()
	self:stopBatteryWatcher()
	self:stopDeferredRefreshCheck()
end

function ReaderHeaderFooter:onResume()
	if not self:isEnabled() then
		self:stopClockWatcher()
		self:stopBatteryWatcher()
		self:stopDeferredRefreshCheck()
		return
	end

	local old_wifi = self.last_wifi_on
	local old_battery = self.last_battery_level
	local old_charging = self.last_charging

	local power = self:getPowerSnapshot()

	self.last_wifi_on = self:getWifiState()
	self.last_battery_level = power.level
	self.last_charging = power.charging

	if
		old_wifi ~= self.last_wifi_on
		or old_battery ~= self.last_battery_level
		or old_charging ~= self.last_charging
	then
		self:requestTopIndicatorRefresh()
	end

	self:startClockWatcher()
	self:startBatteryWatcher()
	self:scheduleDeferredRefreshCheck()
end

return ReaderHeaderFooter
