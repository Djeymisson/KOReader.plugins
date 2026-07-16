return function(ctx)
	setmetatable(ctx, { __index = _G })
	setfenv(1, ctx)

	local function runCallback(callback)
		if callback then
			return callback()
		end
		return true
	end

	local function tapEvent(name, dimen)
		return {
			[name] = {
				GestureRange:new({
					ges = "tap",
					range = dimen,
				}),
			},
		}
	end

	local function clamp(value, min_value, max_value)
		return math.max(min_value, math.min(max_value, value))
	end

	local function makeTextLabel(text, face, max_width, bold)
		return TextWidget:new({
			text = text or "",
			face = face,
			bold = bold and true or false,
			max_width = math.max(1, max_width or 1),
		})
	end

	local PAGE_DOT_FACE = Font:getFace("cfont", math.max(14, (HEADER_BUTTON_FONT_SIZE or UI_FONT_SIZE or 20) - 5))
	local BUTTON_ROW_SAFETY_WIDTH = math.max(1, Screen:scaleBySize(2))
	local TAB_INACTIVE_TOP_OFFSET = math.max(1, Screen:scaleBySize(3))
	local TAB_LABEL_FACE = Font:getFace("cfont", math.max(13, (HEADER_MENU_FONT_SIZE or UI_FONT_SIZE or 20) - 1))
	local TAB_COMPACT_MIN_WIDTH = math.max(Screen:scaleBySize(46), Screen:scaleBySize(1))
	local TAB_COMPACT_EXTRA_PADDING_H = Screen:scaleBySize(10)
	local TAB_LABEL_MAX_WIDTH = Screen:scaleBySize(160)
	local TAB_HEADER_GAP = math.max(SIDE_TAB_GAP or 0, Screen:scaleBySize(5))
	local function getTabLabel(page_index)
		return PAGE_TITLES[page_index] or EMPTY_TEXT
	end

	local function getTabLabelWidth(text, active)
		local label = makeTextLabel(text or EMPTY_TEXT, TAB_LABEL_FACE, TAB_LABEL_MAX_WIDTH, active)
		local size = getWidgetSize(label)
		return size and size.w or 0
	end

	local function getCompactTabWidth(text, active)
		local label_width = getTabLabelWidth(text, active)
		return math.max(
			TAB_COMPACT_MIN_WIDTH,
			label_width + 2 * SIDE_TAB_PADDING_H + 2 * SIDE_TAB_BORDER_SIZE + TAB_COMPACT_EXTRA_PADDING_H
		)
	end

	local function makeCenteredFrame(label, width, height, padding_h, padding_v, show_parent)
		padding_h = padding_h or 0
		padding_v = padding_v or 0

		return FrameContainer:new({
			show_parent = show_parent,
			bordersize = 0,
			background = Blitbuffer.COLOR_WHITE,
			padding_left = padding_h,
			padding_right = padding_h,
			padding_top = padding_v,
			padding_bottom = padding_v,
			CenterContainer:new({
				dimen = Geom:new({
					w = math.max(1, width - 2 * padding_h),
					h = math.max(1, height - 2 * padding_v),
				}),
				label,
			}),
		})
	end

	local function makeSideTab(text, width, height, active)
		local label = makeTextLabel(text, HEADER_MENU_FACE, math.max(1, width - 2 * SIDE_TAB_PADDING_H), active)

		return FrameContainer:new({
			background = Blitbuffer.COLOR_WHITE,
			bordersize = SIDE_TAB_BORDER_SIZE,
			color = active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_GRAY,
			margin = 0,
			padding_left = SIDE_TAB_PADDING_H,
			padding_right = SIDE_TAB_PADDING_H,
			padding_top = SIDE_TAB_PADDING_V,
			padding_bottom = SIDE_TAB_PADDING_V,
			CenterContainer:new({
				dimen = Geom:new({
					w = math.max(1, width - 2 * SIDE_TAB_PADDING_H),
					h = math.max(1, height - 2 * SIDE_TAB_PADDING_V),
				}),
				label,
			}),
		})
	end

	HeaderSubtitleButton = InputContainer:extend({
		text = nil,
		face = nil,
		width = nil,
		height = nil,
		callback = nil,
		show_parent = nil,
	})

	function HeaderSubtitleButton:init()
		local width = self.width or Screen:scaleBySize(240)
		local label = makeTextLabel(self.text, self.face or SUBTITLE_FACE, width)
		local label_size = getWidgetSize(label)
		local height = self.height or math.max(1, label_size.h or Screen:scaleBySize(14))

		self.frame = FrameContainer:new({
			show_parent = self.show_parent,
			bordersize = 0,
			background = Blitbuffer.COLOR_WHITE,
			padding = 0,
			label,
		})

		self.dimen = Geom:new({ x = 0, y = 0, w = width, h = height })
		self[1] = self.frame
		self.ges_events = tapEvent("TapHeaderSubtitle", self.dimen)
	end

	function HeaderSubtitleButton:onTapHeaderSubtitle()
		return runCallback(self.callback)
	end

	HeaderPageButton = InputContainer:extend({
		text = nil,
		width = nil,
		face = nil,
		bold = nil,
		callback = nil,
		show_parent = nil,
	})

	function HeaderPageButton:init()
		local width = self.width or HEADER_MENU_WIDTH
		local label_width = width - 2 * HEADER_MENU_PADDING_H
		local label = makeTextLabel(self.text, self.face or HEADER_BUTTON_FACE, label_width, self.bold ~= false)

		self.frame = makeCenteredFrame(
			label,
			width,
			HEADER_MENU_HEIGHT,
			HEADER_MENU_PADDING_H,
			HEADER_MENU_PADDING_V,
			self.show_parent
		)

		self.dimen = Geom:new({ x = 0, y = 0, w = width, h = HEADER_MENU_HEIGHT })
		self[1] = self.frame
		self.ges_events = tapEvent("TapHeaderPageMenu", self.dimen)
	end

	function HeaderPageButton:onTapHeaderPageMenu()
		return runCallback(self.callback)
	end

	HeaderPageDotsButton = InputContainer:extend({
		active_index = PAGE_DICTIONARY,
		width = nil,
		height = HEADER_MENU_HEIGHT,
		callback = nil,
		show_parent = nil,
	})

	function HeaderPageDotsButton:init()
		local width = self.width or Screen:scaleBySize(66)
		local height = self.height or HEADER_MENU_HEIGHT
		local active_index = tonumber(self.active_index) or PAGE_DICTIONARY
		local dot_width = math.max(1, math.floor(width / 3))
		local widgets = {}

		for index = PAGE_DICTIONARY, PAGE_WIKIPEDIA do
			widgets[#widgets + 1] = CenterContainer:new({
				dimen = Geom:new({ w = dot_width, h = height }),
				makeTextLabel(index == active_index and "●" or "○", PAGE_DOT_FACE, dot_width, false),
			})
		end

		self.frame = FrameContainer:new({
			show_parent = self.show_parent,
			bordersize = 0,
			background = Blitbuffer.COLOR_WHITE,
			padding = 0,
			CenterContainer:new({
				dimen = Geom:new({ w = width, h = height }),
				HorizontalGroup:new(widgets),
			}),
		})

		self.dimen = Geom:new({ x = 0, y = 0, w = width, h = height })
		self[1] = self.frame
		self.ges_events = tapEvent("TapHeaderPageDots", self.dimen)
	end

	function HeaderPageDotsButton:onTapHeaderPageDots()
		return runCallback(self.callback)
	end

	CardTabButton = InputContainer:extend({
		text = nil,
		width = nil,
		height = SIDE_TAB_HEIGHT,
		active = false,
		callback = nil,
		show_parent = nil,
	})

	function CardTabButton:init()
		local width = self.width or Screen:scaleBySize(80)
		local height = self.height or SIDE_TAB_HEIGHT
		local border_size = SIDE_TAB_BORDER_SIZE
		self.top_offset = self.active and 0 or TAB_INACTIVE_TOP_OFFSET
		self.frame_height = math.max(1, height - self.top_offset)
		self.content_width = math.max(1, width - 2 * SIDE_TAB_PADDING_H - 2 * border_size)
		self.content_height = math.max(1, self.frame_height - 2 * SIDE_TAB_PADDING_V - 2 * border_size)

		-- Paint the tab label manually instead of relying on the nested container tree.
		-- On some Kindle builds, the Windows 98-style nested frame is painted correctly,
		-- but the TextWidget inside the CenterContainer may be clipped away. Keeping the
		-- frame and the label as separate widgets preserves the tab shape and makes the
		-- text render reliably.
		self.label = makeTextLabel(self.text or "", TAB_LABEL_FACE, self.content_width, self.active)
		self.frame = FrameContainer:new({
			show_parent = self.show_parent,
			background = Blitbuffer.COLOR_WHITE,
			bordersize = border_size,
			color = self.active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_GRAY,
			margin = 0,
			padding = 0,
			CenterContainer:new({
				dimen = Geom:new({
					w = math.max(1, width - 2 * border_size),
					h = math.max(1, self.frame_height - 2 * border_size),
				}),
				HorizontalSpan:new({ width = 1 }),
			}),
		})

		if self.active then
			self.bottom_cover = LineWidget:new({
				background = Blitbuffer.COLOR_WHITE,
				dimen = Geom:new({
					w = math.max(1, width - 2 * border_size),
					h = border_size,
				}),
			})
		end

		self.dimen = Geom:new({ x = 0, y = 0, w = width, h = height })
		self[1] = self.frame
		self.ges_events = tapEvent("TapCardTab", self.dimen)
	end

	function CardTabButton:getSize()
		return self.dimen
	end

	function CardTabButton:paintTo(bb, x, y)
		x = x or (self.dimen and self.dimen.x) or 0
		y = y or (self.dimen and self.dimen.y) or 0

		local width = (self.dimen and self.dimen.w) or (self.width or Screen:scaleBySize(80))
		local height = (self.dimen and self.dimen.h) or (self.height or SIDE_TAB_HEIGHT)
		local top_offset = self.top_offset or 0
		local frame_height = self.frame_height or math.max(1, height - top_offset)

		if self.dimen then
			self.dimen.x = x
			self.dimen.y = y
			self.dimen.w = width
			self.dimen.h = height
		end

		if self.frame then
			if self.frame.dimen then
				self.frame.dimen.x = x
				self.frame.dimen.y = y + top_offset
				self.frame.dimen.w = width
				self.frame.dimen.h = frame_height
			end
			self.frame:paintTo(bb, x, y + top_offset)
		end

		if self.bottom_cover then
			self.bottom_cover.dimen = Geom:new({
				x = x + SIDE_TAB_BORDER_SIZE,
				y = y + top_offset + frame_height - SIDE_TAB_BORDER_SIZE,
				w = math.max(1, width - 2 * SIDE_TAB_BORDER_SIZE),
				h = SIDE_TAB_BORDER_SIZE,
			})
			self.bottom_cover:paintTo(
				bb,
				x + SIDE_TAB_BORDER_SIZE,
				y + top_offset + frame_height - SIDE_TAB_BORDER_SIZE
			)
		end

		if self.label then
			local label_size = getWidgetSize(self.label)
			local label_width = label_size.w or self.content_width or width
			local label_height = label_size.h or self.content_height or frame_height
			local label_x = x + math.floor((width - label_width) / 2)
			local label_y = y + top_offset + math.floor((frame_height - label_height) / 2)
			self.label:paintTo(bb, label_x, label_y)
		end
	end

	function CardTabButton:onTapCardTab()
		return runCallback(self.callback)
	end

	DictionaryCardButton = InputContainer:extend({
		text = nil,
		icon = nil,
		icon_file = nil,
		width = nil,
		height = DICTIONARY_BUTTON_HEIGHT,
		icon_width = DICTIONARY_ICON_SIZE,
		icon_height = DICTIONARY_ICON_SIZE,
		callback = nil,
		show_parent = nil,
	})

	function DictionaryCardButton:makeLabel(inner_width)
		if self.icon_file then
			return IconWidget:new({
				file = self.icon_file,
				width = self.icon_width,
				height = self.icon_height,
				alpha = true,
				is_icon = true,
			})
		end

		if self.icon then
			return IconWidget:new({
				icon = self.icon,
				width = self.icon_width,
				height = self.icon_height,
				alpha = true,
			})
		end

		return makeTextLabel(self.text, DICTIONARY_BUTTON_FACE, inner_width, true)
	end

	function DictionaryCardButton:init()
		local width = self.width or Screen:scaleBySize(64)
		local height = self.height or DICTIONARY_BUTTON_HEIGHT
		local padding_h = math.max(1, math.floor(Size.padding.button * 0.55))
		local padding_v = math.max(0, math.floor(Size.padding.button * 0.25))
		local inner_width = math.max(1, width - 2 * padding_h)
		local inner_height = math.max(1, height - 2 * padding_v)
		local label = self:makeLabel(inner_width)

		self.frame = FrameContainer:new({
			show_parent = self.show_parent,
			bordersize = 0,
			background = Blitbuffer.COLOR_WHITE,
			padding_left = padding_h,
			padding_right = padding_h,
			padding_top = padding_v,
			padding_bottom = padding_v,
			CenterContainer:new({
				dimen = Geom:new({ w = inner_width, h = inner_height }),
				label,
			}),
		})

		self.dimen = Geom:new({ x = 0, y = 0, w = width, h = height })
		self[1] = self.frame
		self.ges_events = tapEvent("TapDictionaryButton", self.dimen)
	end

	function DictionaryCardButton:onTapDictionaryButton()
		return runCallback(self.callback)
	end

	SimplePageMenu = InputContainer:extend({
		parent_popup = nil,
		active_index = PAGE_DICTIONARY,
		anchor_dimen = nil,
		visible_dimen = nil,
		container = nil,
	})

	function SimplePageMenu:makeRow(page_index, width)
		local is_active = page_index == self.active_index
		local label = makeTextLabel(
			(is_active and "• " or "  ") .. PAGE_TITLES[page_index],
			HEADER_MENU_FACE,
			width - 2 * PAGE_MENU_PADDING_H,
			is_active
		)

		return LeftContainer:new({
			allow_mirroring = false,
			dimen = Geom:new({ w = width, h = PAGE_MENU_ITEM_HEIGHT }),
			HorizontalGroup:new({
				HorizontalSpan:new({ width = PAGE_MENU_PADDING_H }),
				label,
			}),
		})
	end

	function SimplePageMenu:makeContainer(content_width, border_size)
		return FrameContainer:new({
			background = Blitbuffer.COLOR_WHITE,
			bordersize = border_size,
			color = Blitbuffer.COLOR_DARK_GRAY,
			margin = 0,
			padding = 0,
			VerticalGroup:new({
				self:makeRow(PAGE_DICTIONARY, content_width),
				self:makeRow(PAGE_TRANSLATION, content_width),
				self:makeRow(PAGE_WIKIPEDIA, content_width),
			}),
		})
	end

	function SimplePageMenu:getPosition(width, height, screen_width, screen_height)
		local parent_dimen = self.parent_popup and self.parent_popup.visible_dimen
		local anchor = self.anchor_dimen
		local x = anchor and (anchor.x + anchor.w - width) or math.floor((screen_width - width) / 2)
		x = clamp(x, CARD_EDGE_MARGIN, screen_width - width - CARD_EDGE_MARGIN)

		local y
		if anchor then
			-- Keep the selector inside the active card area instead of placing it
			-- above the popup over the reader text.
			y = anchor.y + anchor.h + PAGE_MENU_GAP
		elseif parent_dimen then
			y = parent_dimen.y + CARD_BORDER_SIZE + CARD_PADDING_TOP
		else
			y = math.floor((screen_height - height) / 2)
		end

		if parent_dimen then
			local min_y = parent_dimen.y + CARD_BORDER_SIZE
			local max_y = parent_dimen.y + parent_dimen.h - height - CARD_BORDER_SIZE
			if max_y >= min_y then
				y = clamp(y, min_y, max_y)
			else
				y = clamp(y, CARD_EDGE_MARGIN, screen_height - height - CARD_EDGE_MARGIN)
			end
		else
			y = clamp(y, CARD_EDGE_MARGIN, screen_height - height - CARD_EDGE_MARGIN)
		end

		return x, y
	end

	function SimplePageMenu:init()
		local screen_width = Screen:getWidth()
		local screen_height = Screen:getHeight()
		local border_size = Size.border.thin
		local content_width = math.min(PAGE_MENU_WIDTH, screen_width - 2 * CARD_EDGE_MARGIN - 2 * border_size)

		self.container = self:makeContainer(content_width, border_size)

		local container_size = getWidgetSize(self.container)
		local width = container_size.w and container_size.w > 0 and container_size.w or content_width + 2 * border_size
		local height = container_size.h and container_size.h > 0 and container_size.h
			or PAGE_MENU_ITEM_HEIGHT * 3 + 2 * border_size
		local x, y = self:getPosition(width, height, screen_width, screen_height)

		self.visible_dimen = Geom:new({ x = x, y = y, w = width, h = height })
		self.dimen = Screen:getSize()

		self[1] = TopContainer:new({
			dimen = Screen:getSize(),
			VerticalGroup:new({
				VerticalSpan:new({ width = y }),
				HorizontalGroup:new({
					HorizontalSpan:new({ width = x }),
					self.container,
				}),
			}),
		})

		if IS_TOUCH_DEVICE then
			self.ges_events = tapEvent("TapPageMenu", self.dimen)
		end

		if HAS_KEYS then
			self.key_events = {
				Close = { { Device.input.group.Back } },
			}
		end
	end

	function SimplePageMenu:onShow()
		UIManager:setDirty(self.parent_popup and self.parent_popup.dialog or self, function()
			return "ui", self.visible_dimen or Screen:getSize()
		end)
	end

	function SimplePageMenu:onCloseWidget()
		UIManager:setDirty(self.parent_popup and self.parent_popup.dialog or self, function()
			return "partial", self.visible_dimen or Screen:getSize()
		end)
	end

	function SimplePageMenu:onClose()
		if self.parent_popup then
			self.parent_popup.page_menu = nil
		end
		UIManager:close(self)
		return true
	end

	function SimplePageMenu:getPageIndexFromTap(y)
		local item_index = math.floor((y - self.visible_dimen.y) / PAGE_MENU_ITEM_HEIGHT) + 1
		if item_index == 2 then
			return PAGE_TRANSLATION
		elseif item_index >= 3 then
			return PAGE_WIKIPEDIA
		end
		return PAGE_DICTIONARY
	end

	function SimplePageMenu:onTapPageMenu(_arg, ges)
		if not ges or not ges.pos or not self.visible_dimen then
			return false
		end

		if ges.pos:notIntersectWith(self.visible_dimen) then
			if self.parent_popup then
				self.parent_popup:closePageMenu()
			else
				UIManager:close(self)
			end
			return true
		end

		local parent = self.parent_popup
		local page_index = self:getPageIndexFromTap(ges.pos.y)
		if parent then
			parent:closePageMenu()
			return parent.plugin:switchToPage(page_index)
		end

		UIManager:close(self)
		return true
	end

	CarouselRow = InputContainer:extend({
		popup = nil,
		active_index = PAGE_DICTIONARY,
		screen_width = nil,
		card_width = nil,
		card_height = nil,
		cards = nil,
		active_card = nil,
		active_container = nil,
		positions = nil,
		shadow_widgets = nil,
		side_tab_widgets = nil,
		side_tab_bounds = nil,
		side_tab_position = nil,
		card_y = 0,
	})

	function CarouselRow:init()
		self.screen_width = self.screen_width or Screen:getWidth()
		self.card_width = self.card_width or math.floor(self.screen_width * CARD_WIDTH_RATIO)
		self.card_height = self.card_height or math.floor(Screen:getHeight() * CARD_HEIGHT_RATIO)
		self.active_index = self.active_index or PAGE_DICTIONARY
		self.cards = {}
		self.shadow_widgets = {}
		self.side_tab_widgets = {}
		self.side_tab_bounds = {}

		self.side_tab_position = nil
		self.card_y = 0
		self.dimen = Geom:new({
			x = 0,
			y = 0,
			w = self.screen_width,
			h = self.card_height,
		})

		self:buildCardPositions()
		self:buildVisibleCards()

		-- The centered card must remain in the widget tree so ScrollHtmlWidget can
		-- receive pan/tap events. Side cards are painted manually in Full cards mode.
		self:buildActiveContainer()
	end

	function CarouselRow:useTabsMode()
		return self.popup
			and self.popup.plugin
			and type(self.popup.plugin.useTabsMode) == "function"
			and self.popup.plugin:useTabsMode()
	end

	function CarouselRow:buildActiveContainer()
		if not self.active_card then
			return
		end

		self.active_container = TopContainer:new({
			dimen = self.dimen,
			VerticalGroup:new({
				VerticalSpan:new({ width = self.card_y or 0 }),
				CenterContainer:new({
					dimen = Geom:new({ w = self.screen_width, h = self.card_height }),
					self.active_card,
				}),
			}),
		})
		self[1] = self.active_container
	end

	function CarouselRow:buildVisibleCards()
		if not self.popup then
			return
		end

		local use_tabs = self:useTabsMode()
		for index = PAGE_DICTIONARY, PAGE_WIKIPEDIA do
			if index == self.active_index or (not use_tabs and math.abs(index - self.active_index) <= 1) then
				local card = self:makeCard(index, index == self.active_index)
				if index == self.active_index then
					self.active_card = card
				end
			end
		end
	end

	function CarouselRow:buildCardPositions()
		local active_x = math.floor((self.screen_width - self.card_width) / 2)
		self.positions = {
			[self.active_index - 1] = active_x - self.card_width - CARD_GAP,
			[self.active_index] = active_x,
			[self.active_index + 1] = active_x + self.card_width + CARD_GAP,
		}
	end

	function CarouselRow:buildSideTabs()
		self.side_tab_widgets = {}
		self.side_tab_bounds = {}

		local active_x = self.positions and self.positions[self.active_index]
		if not active_x then
			return
		end

		local height = SIDE_TAB_HEIGHT
		local base_width = math.max(1, math.floor(self.card_width / 3))
		local y = 0

		for page_index = PAGE_DICTIONARY, PAGE_WIKIPEDIA do
			local offset = page_index - PAGE_DICTIONARY
			local width = page_index == PAGE_WIKIPEDIA and math.max(1, self.card_width - base_width * 2) or base_width
			local x = active_x + offset * base_width

			self.side_tab_widgets[page_index] =
				makeSideTab(PAGE_TITLES[page_index], width, height, page_index == self.active_index)
			self.side_tab_bounds[page_index] = Geom:new({
				x = x,
				y = y,
				w = width,
				h = height,
			})
		end
	end

	function CarouselRow:paintSideTabs(bb, base_x, base_y)
		if not self:useTabsMode() then
			return
		end

		for page_index, widget in pairs(self.side_tab_widgets or {}) do
			local bounds = self.side_tab_bounds and self.side_tab_bounds[page_index]
			if widget and bounds then
				local x = (base_x or 0) + bounds.x
				local y = (base_y or 0) + bounds.y
				if widget.dimen then
					widget.dimen.x = x
					widget.dimen.y = y
					widget.dimen.w = bounds.w
					widget.dimen.h = bounds.h
				end
				widget:paintTo(bb, x, y)
			end
		end
	end

	function CarouselRow:getSideTabPage(pos, row_y)
		if not self:useTabsMode() or type(pos) ~= "table" then
			return nil
		end

		for page_index, bounds in pairs(self.side_tab_bounds or {}) do
			local absolute_bounds = Geom:new({
				x = bounds.x,
				y = (row_y or 0) + bounds.y,
				w = bounds.w,
				h = bounds.h,
			})

			if type(pos.notIntersectWith) == "function" then
				if not pos:notIntersectWith(absolute_bounds) then
					return page_index
				end
			elseif pos.x and pos.y then
				if
					pos.x >= absolute_bounds.x
					and pos.x <= absolute_bounds.x + absolute_bounds.w
					and pos.y >= absolute_bounds.y
					and pos.y <= absolute_bounds.y + absolute_bounds.h
				then
					return page_index
				end
			end
		end

		return nil
	end

	function CarouselRow:getSize()
		return self.dimen
	end

	function CarouselRow:paintCardShadow(bb, base_x, base_y, index)
		if not CARD_SHADOW_ENABLED or CARD_SHADOW_OFFSET <= 0 then
			return
		end

		local shadow = self.shadow_widgets and self.shadow_widgets[index]
		local card_x = self.positions and self.positions[index]
		if not shadow or not card_x then
			return
		end

		local x = (base_x or 0) + card_x + CARD_SHADOW_OFFSET
		local y = (base_y or 0) + (self.card_y or 0) + CARD_SHADOW_OFFSET
		if shadow.dimen then
			shadow.dimen.x = x
			shadow.dimen.y = y
			shadow.dimen.w = self.card_width
			shadow.dimen.h = self.card_height
		end
		shadow:paintTo(bb, x, y)
	end

	function CarouselRow:paintCard(bb, base_x, base_y, index)
		local card = self.cards and self.cards[index]
		local card_x = self.positions and self.positions[index]
		if not card or not card_x then
			return
		end

		local x = (base_x or 0) + card_x
		local y = (base_y or 0) + (self.card_y or 0)
		self:paintCardShadow(bb, base_x, base_y, index)

		if card.dimen then
			card.dimen.x = x
			card.dimen.y = y
			card.dimen.w = self.card_width
			card.dimen.h = self.card_height
		end
		card:paintTo(bb, x, y)
	end

	function CarouselRow:paintTo(bb, x, y)
		x = x or (self.dimen and self.dimen.x) or 0
		y = y or (self.dimen and self.dimen.y) or 0

		if not self:useTabsMode() then
			self:paintCard(bb, x, y, self.active_index - 1)
			self:paintCard(bb, x, y, self.active_index + 1)
		end

		if self.active_container then
			self:paintCardShadow(bb, x, y, self.active_index)
			self.active_container:paintTo(bb, x, y)
		else
			self:paintCard(bb, x, y, self.active_index)
		end
	end

	function CarouselRow:makeCard(index, is_active)
		local popup = self.popup
		if not popup then
			return nil
		end

		local payload = popup.plugin:getPagePayload(popup.state, index, is_active)
		local card = popup:makeCard(payload, self.card_width, self.card_height)
		self.cards[index] = card

		if CARD_SHADOW_ENABLED and CARD_SHADOW_OFFSET > 0 and not self.shadow_widgets[index] then
			self.shadow_widgets[index] = LineWidget:new({
				background = CARD_SHADOW_COLOR,
				dimen = Geom:new({ w = self.card_width, h = self.card_height }),
			})
		end

		return card
	end

	function CarouselRow:replaceActiveCard()
		local card = self:makeCard(self.active_index, true)
		if not card then
			return false
		end

		self.active_card = card
		self:buildActiveContainer()
		return true
	end

	function CarouselRow:rebuildForPage(index)
		self.active_index = index or PAGE_DICTIONARY
		self.cards = {}
		self.shadow_widgets = {}
		self.side_tab_widgets = {}
		self.side_tab_bounds = {}
		self.active_card = nil
		self.active_container = nil

		self:buildCardPositions()
		self:buildVisibleCards()

		self:buildActiveContainer()
		return true
	end

	LookupPreviewPopup = InputContainer:extend({
		plugin = nil,
		state = nil,
		active_index = PAGE_DICTIONARY,
		selection_bounds = nil,
		dialog = nil,
		anchor_top = false,
		card_container = nil,
		visible_dimen = nil,
		page_menu = nil,
	})

	function LookupPreviewPopup:shouldAnchorTop(row_height)
		local bounds = self.selection_bounds
		if type(bounds) ~= "table" or not bounds.top or not bounds.bottom then
			return false
		end

		local screen_height = Screen:getHeight()
		local top_card_bottom = CARD_EDGE_MARGIN + row_height
		local bottom_card_top = screen_height - CARD_EDGE_MARGIN - row_height

		if bottom_card_top > bounds.bottom + FLOATING_SELECTION_GAP then
			return false
		end
		if top_card_bottom < bounds.top - FLOATING_SELECTION_GAP then
			return true
		end

		local space_above = math.max(0, bounds.top - CARD_EDGE_MARGIN - FLOATING_SELECTION_GAP)
		local space_below = math.max(0, screen_height - bounds.bottom - CARD_EDGE_MARGIN - FLOATING_SELECTION_GAP)
		return space_above > space_below
	end

	function LookupPreviewPopup:makeHeaderText(text, face, bold, callback, width)
		local widget
		if callback then
			widget = HeaderSubtitleButton:new({
				text = text or EMPTY_TEXT,
				face = face,
				width = width,
				show_parent = self,
				callback = callback,
			})
		else
			widget = makeTextLabel(text or EMPTY_TEXT, face, width, bold)
		end

		local size = getWidgetSize(widget)
		return LeftContainer:new({
			allow_mirroring = false,
			dimen = Geom:new({ w = width, h = math.max(1, size.h or Screen:scaleBySize(14)) }),
			widget,
		})
	end

	function LookupPreviewPopup:makeHeader(payload, content_width)
		payload = payload or {}

		local menu_button
		local menu_width = 0
		if not self:useTabsMode() then
			local active_page = payload.page_type or self.active_index or PAGE_DICTIONARY
			menu_width = math.max(HEADER_MENU_WIDTH, Screen:scaleBySize(66))
			menu_button = HeaderPageDotsButton:new({
				active_index = active_page,
				width = menu_width,
				show_parent = self,
				callback = function()
					return self:showPageMenu()
				end,
			})
		end

		local text_width = menu_button and math.max(1, content_width - menu_width - HEADER_TITLE_MENU_GAP)
			or content_width
		local text_items = {
			self:makeHeaderText(payload.title or EMPTY_TEXT, TITLE_FACE, true, nil, text_width),
		}

		if payload.subtitle and payload.subtitle ~= "" then
			text_items[#text_items + 1] = VerticalSpan:new({ width = HEADER_GAP })
			text_items[#text_items + 1] =
				self:makeHeaderText(payload.subtitle, SUBTITLE_FACE, false, payload.subtitle_callback, text_width)
		end

		local text_block = VerticalGroup:new(text_items)
		local row_height = getWidgetSize(text_block).h or Screen:scaleBySize(24)
		if menu_button then
			row_height = math.max(row_height, getWidgetSize(menu_button).h or HEADER_MENU_HEIGHT)
		end

		local row_items = {
			LeftContainer:new({
				allow_mirroring = false,
				dimen = Geom:new({ w = text_width, h = row_height }),
				text_block,
			}),
		}

		if menu_button then
			row_items[#row_items + 1] = HorizontalSpan:new({ width = HEADER_TITLE_MENU_GAP })
			row_items[#row_items + 1] = CenterContainer:new({
				dimen = Geom:new({ w = menu_width, h = row_height }),
				menu_button,
			})
		end

		return VerticalGroup:new({
			HorizontalGroup:new(row_items),
			VerticalSpan:new({ width = HEADER_SEPARATOR_GAP }),
			LineWidget:new({
				background = Blitbuffer.COLOR_GRAY,
				dimen = Geom:new({ w = content_width, h = math.max(1, Screen:scaleBySize(1)) }),
			}),
			VerticalSpan:new({ width = HEADER_SEPARATOR_GAP }),
		})
	end

	function LookupPreviewPopup:getButtonWidths(button_specs, content_width)
		local separator_count = math.max(0, #button_specs - 1)
		local safe_content_width = math.max(1, content_width - BUTTON_ROW_SAFETY_WIDTH)
		local available_width = math.max(1, safe_content_width - DICTIONARY_BUTTON_SEPARATOR_WIDTH * separator_count)
		local weights = {}
		local total_weight = 0

		for index, item in ipairs(button_specs) do
			local weight = tonumber(item.weight) or 1
			if weight <= 0 then
				weight = 1
			end
			weights[index] = weight
			total_weight = total_weight + weight
		end

		local widths = {}
		local used_width = 0
		for index = 1, #button_specs do
			if index == #button_specs then
				widths[index] = math.max(1, available_width - used_width)
			else
				widths[index] = math.max(1, math.floor(available_width * weights[index] / total_weight))
				used_width = used_width + widths[index]
			end
		end

		return widths
	end

	function LookupPreviewPopup:makeDictionaryButtons(payload, content_width)
		local button_specs = payload and (payload.card_buttons or payload.dictionary_buttons)
		if type(button_specs) ~= "table" or #button_specs == 0 then
			return nil
		end

		local widths = self:getButtonWidths(button_specs, content_width)
		local widgets = {}
		for index, item in ipairs(button_specs) do
			if index > 1 then
				widgets[#widgets + 1] = LineWidget:new({
					background = Blitbuffer.COLOR_GRAY,
					dimen = Geom:new({ w = DICTIONARY_BUTTON_SEPARATOR_WIDTH, h = DICTIONARY_BUTTON_HEIGHT }),
				})
			end

			local spec = item.spec or {}
			widgets[#widgets + 1] = DictionaryCardButton:new({
				text = spec.text,
				icon = spec.icon,
				icon_file = spec.icon_file,
				width = widths[index],
				height = DICTIONARY_BUTTON_HEIGHT,
				icon_width = DICTIONARY_ICON_SIZE,
				icon_height = DICTIONARY_ICON_SIZE,
				show_parent = self,
				callback = item.callback,
			})
		end

		return HorizontalGroup:new(widgets)
	end

	function LookupPreviewPopup:useTabsMode()
		return self.plugin and type(self.plugin.useTabsMode) == "function" and self.plugin:useTabsMode()
	end

	function LookupPreviewPopup:makeCardTabs(content_width, active_index)
		if not self:useTabsMode() then
			return nil
		end

		active_index = active_index or self.active_index or PAGE_DICTIONARY
		local specs = {}
		local used_width = 0

		for page_index = PAGE_DICTIONARY, PAGE_WIKIPEDIA do
			local active = page_index == active_index
			local text = getTabLabel(page_index)
			local width = getCompactTabWidth(text, active)
			specs[#specs + 1] = {
				page_index = page_index,
				text = text,
				width = width,
				active = active,
			}
			used_width = used_width + width
		end

		if used_width > content_width then
			local base_width = math.max(1, math.floor(content_width / 3))
			used_width = 0
			for index, spec in ipairs(specs) do
				spec.width = index == #specs and math.max(1, content_width - base_width * (#specs - 1)) or base_width
				used_width = used_width + spec.width
			end
		end

		local row_items = {}
		local bottom_segments = {}

		for _, spec in ipairs(specs) do
			row_items[#row_items + 1] = CardTabButton:new({
				text = spec.text,
				width = spec.width,
				height = SIDE_TAB_HEIGHT,
				active = spec.active,
				show_parent = self,
				callback = function()
					return self.plugin:switchToPage(spec.page_index)
				end,
			})

			bottom_segments[#bottom_segments + 1] = LineWidget:new({
				background = spec.active and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_GRAY,
				dimen = Geom:new({ w = spec.width, h = SIDE_TAB_BORDER_SIZE }),
			})
		end

		local filler_width = math.max(0, content_width - used_width)
		if filler_width > 0 then
			row_items[#row_items + 1] = HorizontalSpan:new({ width = filler_width })
			bottom_segments[#bottom_segments + 1] = LineWidget:new({
				background = Blitbuffer.COLOR_GRAY,
				dimen = Geom:new({ w = filler_width, h = SIDE_TAB_BORDER_SIZE }),
			})
		end

		return VerticalGroup:new({
			HorizontalGroup:new(row_items),
			HorizontalGroup:new(bottom_segments),
		})
	end
	function LookupPreviewPopup:getCardDimensions(card_width, card_height, header, buttons, page_type, tabs)
		local header_height = getWidgetSize(header).h or Screen:scaleBySize(46)
		local tabs_height = tabs and (getWidgetSize(tabs).h or SIDE_TAB_HEIGHT) or 0
		local tabs_gap = tabs and TAB_HEADER_GAP or 0
		local button_height = page_type == PAGE_TRANSLATION and TRANSLATION_BUTTON_HEIGHT or DICTIONARY_BUTTON_HEIGHT
		local button_gap = page_type == PAGE_TRANSLATION and TRANSLATION_BUTTON_GAP or DICTIONARY_BUTTON_GAP
		local buttons_height = buttons and (getWidgetSize(buttons).h or button_height) or 0
		local buttons_gap = buttons and button_gap or 0
		local html_height = math.max(
			MIN_HTML_HEIGHT,
			card_height
				- tabs_height
				- tabs_gap
				- header_height
				- buttons_height
				- buttons_gap
				- CARD_PADDING_TOP
				- CARD_PADDING_BOTTOM
				- 2 * CARD_BORDER_SIZE
		)

		return html_height, buttons_gap
	end

	function LookupPreviewPopup:getCardRadius()
		if self.plugin and type(self.plugin.getCardRadius) == "function" then
			return self.plugin:getCardRadius()
		end
		return CARD_RADIUS
	end

	function LookupPreviewPopup:makeCard(payload, card_width, card_height)
		payload = payload or {}
		local content_width = math.max(1, card_width - 2 * CARD_PADDING_H - 2 * CARD_BORDER_SIZE)
		local tabs = self:makeCardTabs(content_width, payload.page_type or self.active_index)
		local header = self:makeHeader(payload, content_width)
		local buttons = self:makeDictionaryButtons(payload, content_width)
		local html_height, buttons_gap =
			self:getCardDimensions(card_width, card_height, header, buttons, payload.page_type, tabs)

		local html_widget = ScrollHtmlWidget:new({
			html_body = payload.html_body or "",
			is_xhtml = true,
			css = payload.css or FALLBACK_CSS,
			html_resource_directory = payload.html_resource_directory,
			default_font_size = BODY_FONT_SIZE,
			width = content_width,
			height = html_height,
			scroll_bar_width = SCROLL_BAR_WIDTH,
			text_scroll_span = TEXT_SCROLL_SPAN,
			dialog = self.dialog,
			highlight_text_selection = false,
		})

		local content_items = {
			VerticalSpan:new({ width = CARD_PADDING_TOP }),
		}

		if tabs then
			content_items[#content_items + 1] = HorizontalGroup:new({
				HorizontalSpan:new({ width = CARD_PADDING_H }),
				tabs,
				HorizontalSpan:new({ width = CARD_PADDING_H }),
			})
			if TAB_HEADER_GAP > 0 then
				content_items[#content_items + 1] = VerticalSpan:new({ width = TAB_HEADER_GAP })
			end
		end

		content_items[#content_items + 1] = HorizontalGroup:new({
			HorizontalSpan:new({ width = CARD_PADDING_H }),
			header,
			HorizontalSpan:new({ width = CARD_PADDING_H }),
		})
		content_items[#content_items + 1] = HorizontalGroup:new({
			HorizontalSpan:new({ width = CARD_PADDING_H }),
			html_widget,
			HorizontalSpan:new({ width = CARD_PADDING_H }),
		})

		if buttons then
			content_items[#content_items + 1] = VerticalSpan:new({ width = buttons_gap })
			content_items[#content_items + 1] = HorizontalGroup:new({
				HorizontalSpan:new({ width = CARD_PADDING_H }),
				buttons,
				HorizontalSpan:new({ width = CARD_PADDING_H }),
			})
		end
		content_items[#content_items + 1] = VerticalSpan:new({ width = CARD_PADDING_BOTTOM })

		return FrameContainer:new({
			background = Blitbuffer.COLOR_WHITE,
			bordersize = CARD_BORDER_SIZE,
			color = CARD_BORDER_COLOR,
			radius = self:getCardRadius(),
			margin = 0,
			padding = 0,
			VerticalGroup:new(content_items),
		}),
			Geom:new({ w = card_width, h = card_height })
	end

	function LookupPreviewPopup:makeRow(card_width, card_height)
		local row = CarouselRow:new({
			popup = self,
			active_index = self.active_index or PAGE_DICTIONARY,
			screen_width = Screen:getWidth(),
			card_width = card_width,
			card_height = card_height,
		})
		local row_size = getWidgetSize(row)
		return row, row_size.h or card_height
	end

	function LookupPreviewPopup:init()
		local screen_width = Screen:getWidth()
		local screen_height = Screen:getHeight()
		local card_height = math.floor(screen_height * CARD_HEIGHT_RATIO)
		local card_width = math.max(CARD_MIN_WIDTH, math.floor(screen_width * CARD_WIDTH_RATIO))
		card_width = math.min(card_width, screen_width - 2 * CARD_EDGE_MARGIN)
		self.card_width = card_width
		self.card_height = card_height

		if IS_TOUCH_DEVICE then
			local range = Geom:new({ x = 0, y = 0, w = screen_width, h = screen_height })
			self.ges_events = {
				TapClose = { GestureRange:new({ ges = "tap", range = range }) },
				SwipePage = { GestureRange:new({ ges = "swipe", range = range }) },
			}
		end

		if HAS_KEYS then
			self.key_events = {
				Close = { { Device.input.group.Back } },
			}
		end

		self.anchor_top = self:shouldAnchorTop(card_height)
		local row, row_height = self:makeRow(card_width, card_height)
		self.card_container = row

		local y
		if self.anchor_top then
			y = CARD_EDGE_MARGIN
			self[1] = TopContainer:new({
				dimen = Screen:getSize(),
				VerticalGroup:new({
					VerticalSpan:new({ width = CARD_EDGE_MARGIN }),
					row,
				}),
			})
		else
			y = screen_height - CARD_EDGE_MARGIN - row_height
			self[1] = BottomContainer:new({
				dimen = Screen:getSize(),
				VerticalGroup:new({
					row,
					VerticalSpan:new({ width = CARD_EDGE_MARGIN }),
				}),
			})
		end

		local visible_height = row_height + (CARD_SHADOW_ENABLED and CARD_SHADOW_OFFSET or 0)
		self.visible_dimen = Geom:new({ x = 0, y = y, w = screen_width, h = visible_height })
	end

	function LookupPreviewPopup:closePageMenu()
		if self.page_menu then
			pcall(function()
				UIManager:close(self.page_menu)
			end)
			self.page_menu = nil
		end
	end

	function LookupPreviewPopup:getPageMenuAnchor()
		local screen_width = Screen:getWidth()
		local card_width = self.card_width or math.max(CARD_MIN_WIDTH, math.floor(screen_width * CARD_WIDTH_RATIO))
		card_width = math.min(card_width, screen_width - 2 * CARD_EDGE_MARGIN)

		local active_x = math.floor((screen_width - card_width) / 2)
		local content_width = math.max(1, card_width - 2 * CARD_PADDING_H - 2 * CARD_BORDER_SIZE)
		return Geom:new({
			x = active_x + CARD_BORDER_SIZE + CARD_PADDING_H + content_width - HEADER_MENU_WIDTH,
			y = ((self.visible_dimen and self.visible_dimen.y) or CARD_EDGE_MARGIN)
				+ CARD_BORDER_SIZE
				+ CARD_PADDING_TOP,
			w = HEADER_MENU_WIDTH,
			h = HEADER_MENU_HEIGHT,
		})
	end

	function LookupPreviewPopup:showPageMenu()
		self:closePageMenu()
		self.page_menu = SimplePageMenu:new({
			parent_popup = self,
			active_index = self.active_index or PAGE_DICTIONARY,
			anchor_dimen = self:getPageMenuAnchor(),
		})
		UIManager:show(self.page_menu)
		return true
	end

	function LookupPreviewPopup:markDirty(mode)
		UIManager:setDirty(self.dialog or self, function()
			return mode or "ui", self.visible_dimen or Screen:getSize()
		end)
	end

	function LookupPreviewPopup:rebuildVisibleCards()
		self:closePageMenu()

		if self.card_container and self.card_container.rebuildForPage then
			self.card_container:rebuildForPage(self.active_index or PAGE_DICTIONARY)
			self:markDirty("ui")
			return true
		end

		return false
	end

	function LookupPreviewPopup:updateCurrentPage(index)
		index = index or self.active_index or PAGE_DICTIONARY
		if index ~= self.active_index then
			return self:switchToPage(index)
		end

		if self.card_container and self.card_container.replaceActiveCard then
			self.card_container:replaceActiveCard()
			self:markDirty("ui")
			return true
		end

		return false
	end

	function LookupPreviewPopup:switchToPage(index)
		index = math.max(PAGE_DICTIONARY, math.min(PAGE_WIKIPEDIA, index or PAGE_DICTIONARY))
		self:closePageMenu()
		self.active_index = index
		if self.state then
			self.state.active_index = index
		end

		if self.card_container and self.card_container.rebuildForPage then
			self.card_container:rebuildForPage(index)
			self:markDirty("ui")
			return true
		end

		return false
	end

	function LookupPreviewPopup:onShow()
		UIManager:setDirty(self.dialog or self, function()
			return "ui", self.visible_dimen or Screen:getSize()
		end)
	end

	function LookupPreviewPopup:onCloseWidget()
		UIManager:setDirty(self.dialog or self, function()
			return "partial", self.visible_dimen or Screen:getSize()
		end)
	end

	function LookupPreviewPopup:onClose()
		self:closePageMenu()
		UIManager:close(self)
		if not self.skip_close_callback and self.plugin then
			return self.plugin:closePreview(false)
		end
		return true
	end

	function LookupPreviewPopup:onTapClose(_arg, ges)
		if not (ges and ges.pos) then
			return false
		end

		if self.visible_dimen and ges.pos:notIntersectWith(self.visible_dimen) then
			return self:onClose()
		end

		if self.card_container and self.card_container.getSideTabPage then
			local page_index =
				self.card_container:getSideTabPage(ges.pos, self.visible_dimen and self.visible_dimen.y or 0)
			if page_index then
				return self.plugin:switchToPage(page_index)
			end
		end

		return false
	end

	function LookupPreviewPopup:onSwipePage(_arg, ges)
		if not ges or not ges.direction then
			return false
		end

		if ges.direction == "west" then
			return self.plugin:switchToPage(math.min(PAGE_WIKIPEDIA, self.active_index + 1))
		elseif ges.direction == "east" then
			return self.plugin:switchToPage(math.max(PAGE_DICTIONARY, self.active_index - 1))
		end

		-- Vertical swipes are reserved for ScrollHtmlWidget inside the active card.
		return false
	end

	function LookupPreviewPopup:onNextPage()
		return self.plugin:switchToPage(math.min(PAGE_WIKIPEDIA, self.active_index + 1))
	end

	function LookupPreviewPopup:onPrevPage()
		return self.plugin:switchToPage(math.max(PAGE_DICTIONARY, self.active_index - 1))
	end
end
