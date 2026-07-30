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
	local BASE_TAB_HEIGHT = SIDE_TAB_HEIGHT or HEADER_MENU_HEIGHT or Screen:scaleBySize(28)
	local TAB_TOUCH_HEIGHT = BASE_TAB_HEIGHT + math.max(2, Screen:scaleBySize(6))
	local TAB_TOUCH_PADDING_H = (SIDE_TAB_PADDING_H or 0) + math.max(2, Screen:scaleBySize(4))
	local TAB_TOUCH_PADDING_V = (SIDE_TAB_PADDING_V or 0) + math.max(1, Screen:scaleBySize(1))
	local TAB_INACTIVE_TOP_OFFSET = math.max(1, Screen:scaleBySize(3))
	local TAB_LABEL_FACE = Font:getFace("cfont", math.max(14, HEADER_MENU_FONT_SIZE or UI_FONT_SIZE or 20))
	local TAB_COMPACT_MIN_WIDTH = math.max(Screen:scaleBySize(58), Screen:scaleBySize(1))
	local TAB_COMPACT_EXTRA_PADDING_H = Screen:scaleBySize(14)
	local TAB_LABEL_MAX_WIDTH = Screen:scaleBySize(180)
	local SHADOW_BAYER8 = {
		{ 0, 32, 8, 40, 2, 34, 10, 42 },
		{ 48, 16, 56, 24, 50, 18, 58, 26 },
		{ 12, 44, 4, 36, 14, 46, 6, 38 },
		{ 60, 28, 52, 20, 62, 30, 54, 22 },
		{ 3, 35, 11, 43, 1, 33, 9, 41 },
		{ 51, 19, 59, 27, 49, 17, 57, 25 },
		{ 15, 47, 7, 39, 13, 45, 5, 37 },
		{ 63, 31, 55, 23, 61, 29, 53, 21 },
	}

	local CardShadow = WidgetContainer:extend({
		width = 0,
		height = 0,
		shadow_width = CARD_SHADOW_WIDTH,
		shadow_overlap = CARD_SHADOW_OVERLAP,
	})

	function CardShadow:_freeBuffers()
		if self._right_bb then
			self._right_bb:free()
			self._right_bb = nil
		end
		if self._bottom_bb then
			self._bottom_bb:free()
			self._bottom_bb = nil
		end
		self._cache_key = nil
	end

	function CardShadow:free()
		self:_freeBuffers()
	end

	function CardShadow:_ensureBuffers(bb)
		local width = math.max(1, self.width or 1)
		local height = math.max(1, self.height or 1)
		local shadow_width = math.max(1, self.shadow_width or CARD_SHADOW_WIDTH)
		local overlap = math.max(0, math.min(shadow_width - 1, self.shadow_overlap or CARD_SHADOW_OVERLAP))
		local bottom_width = width + shadow_width - overlap
		local night = Screen.night_mode
		local inv = bb.getInverse and bb:getInverse() == 1
		local render_inv = inv and not (night and Device.isAndroid and Device:isAndroid())
		local cache_key = table.concat({
			tostring(width),
			tostring(height),
			tostring(shadow_width),
			tostring(overlap),
			tostring(night),
			tostring(render_inv),
		}, ":")
		if self._cache_key == cache_key and self._right_bb and self._bottom_bb then
			return
		end

		self:_freeBuffers()
		self._cache_key = cache_key

		local shadow_value = render_inv and 0x00 or (night and 0xFF or 0x00)
		local base_strength = night and 1.0 or 0.5
		local peak_level = night and 1.0 or 0.62
		local bump_width = 0.18
		local function baseFraction(t)
			if night then
				return t < 0.5 and (1 - 0.8 * t) or 0.6 * (1 - (t - 0.5) * 2) ^ 2
			end
			return 1 - t
		end
		local function shadowLevel(pos)
			local t = (pos + 0.5) / shadow_width
			local original_level = base_strength * baseFraction(t)
			local visible_start = overlap / shadow_width
			local bump
			if t <= visible_start then
				bump = 1
			else
				local distance = (t - visible_start) / bump_width
				bump = distance < 1 and 0.5 * (1 + math.cos(math.pi * distance)) or 0
			end
			return (original_level + bump * (peak_level - original_level)) * 255
		end

		self._right_bb = Blitbuffer.new(shadow_width, height, Blitbuffer.TYPE_BBRGB32)
		for x = 0, shadow_width - 1 do
			local level = shadowLevel(x)
			local column = (x % 8) + 1
			for y = 0, height - 1 do
				local threshold = (SHADOW_BAYER8[column][(y % 8) + 1] + 0.5) * 4
				local alpha = level > threshold and 255 or 0
				self._right_bb:setPixel(x, y, Blitbuffer.ColorRGB32(shadow_value, shadow_value, shadow_value, alpha))
			end
		end
		self._right_bb:setInverse(render_inv and 1 or 0)

		self._bottom_bb = Blitbuffer.new(bottom_width, shadow_width, Blitbuffer.TYPE_BBRGB32)
		for y = 0, shadow_width - 1 do
			local bottom_level = shadowLevel(y)
			local row = (y % 8) + 1
			for x = 0, bottom_width - 1 do
				local level = bottom_level
				if y < overlap and x >= width - overlap then
					level = 0
				elseif x >= width then
					level = math.min(level, shadowLevel(overlap + x - width))
				end
				local threshold = (SHADOW_BAYER8[(x % 8) + 1][row] + 0.5) * 4
				local alpha = level > threshold and 255 or 0
				self._bottom_bb:setPixel(x, y, Blitbuffer.ColorRGB32(shadow_value, shadow_value, shadow_value, alpha))
			end
		end
		self._bottom_bb:setInverse(render_inv and 1 or 0)
	end

	function CardShadow:_alphaBlitClipped(bb, source, x, y)
		local source_x, source_y = 0, 0
		local width, height = source:getWidth(), source:getHeight()
		if x < 0 then
			source_x = -x
			width = width - source_x
			x = 0
		end
		if y < 0 then
			source_y = -y
			height = height - source_y
			y = 0
		end
		width = math.min(width, bb:getWidth() - x)
		height = math.min(height, bb:getHeight() - y)
		if width > 0 and height > 0 then
			bb:alphablitFrom(source, x, y, source_x, source_y, width, height)
		end
	end

	function CardShadow:paintTo(bb, x, y)
		self:_ensureBuffers(bb)
		local width = math.max(1, self.width or 1)
		local height = math.max(1, self.height or 1)
		local overlap = math.max(0, self.shadow_overlap or CARD_SHADOW_OVERLAP)
		self.dimen = Geom:new({
			x = x,
			y = y,
			w = width + CARD_SHADOW_EXTENT,
			h = height + CARD_SHADOW_EXTENT,
		})
		self:_alphaBlitClipped(bb, self._bottom_bb, x, y + height - overlap)
		self:_alphaBlitClipped(bb, self._right_bb, x + width - overlap, y)
	end

	local function popupShowsCardShadows(popup)
		return popup
			and popup.plugin
			and type(popup.plugin.showCardShadows) == "function"
			and popup.plugin:showCardShadows()
	end

	local function getPopupCardRadius(popup)
		if popup and type(popup.getCardRadius) == "function" then
			return popup:getCardRadius()
		end
		return CARD_RADIUS
	end

	local function getRoundedTabRadius(card_radius)
		if not card_radius or card_radius <= 0 then
			return nil
		end
		return math.max(1, math.min(card_radius, math.floor(TAB_TOUCH_HEIGHT / 2)))
	end

	local LookupCardFrame = FrameContainer:extend({
		square_top_left = false,
	})

	function LookupCardFrame:paintTo(bb, x, y)
		FrameContainer.paintTo(self, bb, x, y)
		if not self.square_top_left or not self.radius or self.radius <= 0 then
			return
		end

		local border_size = math.max(1, self.bordersize or 0)
		local margin = self.margin or 0
		local corner_size = math.max(border_size, math.floor(self.radius + border_size))
		local corner_x = x + margin
		local corner_y = y + margin
		bb:paintRect(corner_x, corner_y, corner_size, corner_size, self.background or Blitbuffer.COLOR_WHITE)
		bb:paintRect(corner_x, corner_y, corner_size, border_size, self.color or CARD_BORDER_COLOR)
		bb:paintRect(corner_x, corner_y, border_size, corner_size, self.color or CARD_BORDER_COLOR)
	end

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
		local border_size = active and math.max(SIDE_TAB_BORDER_SIZE or 1, CARD_BORDER_SIZE or 1)
			or SIDE_TAB_BORDER_SIZE
		return math.max(
			TAB_COMPACT_MIN_WIDTH,
			label_width + 2 * TAB_TOUCH_PADDING_H + 2 * border_size + TAB_COMPACT_EXTRA_PADDING_H
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
		height = TAB_TOUCH_HEIGHT,
		active = false,
		radius = nil,
		callback = nil,
		show_parent = nil,
	})

	function CardTabButton:init()
		local width = self.width or Screen:scaleBySize(80)
		local height = self.height or TAB_TOUCH_HEIGHT
		local border_size = self.active and math.max(SIDE_TAB_BORDER_SIZE or 1, CARD_BORDER_SIZE or 1)
			or SIDE_TAB_BORDER_SIZE
		local radius = self.radius and math.max(0, self.radius) or 0
		self.border_size = border_size
		self.radius = radius
		self.use_top_radius = radius > 0
		self.top_offset = self.active and 0 or TAB_INACTIVE_TOP_OFFSET
		self.frame_height = math.max(1, height - self.top_offset)
		self.content_width = math.max(1, width - 2 * TAB_TOUCH_PADDING_H - 2 * border_size)
		self.content_height = math.max(1, self.frame_height - 2 * TAB_TOUCH_PADDING_V - 2 * border_size)

		self.label = makeTextLabel(self.text or "", TAB_LABEL_FACE, self.content_width, self.active)
		self.border_color = self.active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_GRAY
		self.frame = FrameContainer:new({
			show_parent = self.show_parent,
			background = Blitbuffer.COLOR_WHITE,
			bordersize = border_size,
			color = self.border_color,
			radius = nil,
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

	function CardTabButton:paintRoundedFrame(bb, x, y, width, frame_height)
		if not self.use_top_radius then
			return
		end

		local border_size = self.border_size or SIDE_TAB_BORDER_SIZE or 1
		local radius =
			math.max(border_size, math.min(self.radius or 0, math.floor(width / 2), math.floor(frame_height / 2)))
		local background = Blitbuffer.COLOR_WHITE
		local paint_rounded_rect = Blitbuffer.isColor8(background) and bb.paintRoundedRect or bb.paintRoundedRectRGB32
		paint_rounded_rect(bb, x, y, width, frame_height, background, radius + border_size)
		bb:paintBorder(
			x,
			y,
			width,
			frame_height,
			border_size,
			self.border_color,
			radius,
			G_reader_settings:nilOrTrue("anti_alias_ui")
		)

		local square_y = y + radius
		local square_height = frame_height - radius
		if square_height > 0 then
			bb:paintRect(x, square_y, width, square_height, background)
			bb:paintRect(x, square_y, border_size, square_height, self.border_color)
			bb:paintRect(x + width - border_size, square_y, border_size, square_height, self.border_color)
			bb:paintRect(x, y + frame_height - border_size, width, border_size, self.border_color)
		end
	end

	function CardTabButton:paintTo(bb, x, y)
		x = x or (self.dimen and self.dimen.x) or 0
		y = y or (self.dimen and self.dimen.y) or 0

		local width = (self.dimen and self.dimen.w) or (self.width or Screen:scaleBySize(80))
		local height = (self.dimen and self.dimen.h) or (self.height or TAB_TOUCH_HEIGHT)
		local top_offset = self.top_offset or 0
		local frame_height = self.frame_height or math.max(1, height - top_offset)

		if self.dimen then
			self.dimen.x = x
			self.dimen.y = y
			self.dimen.w = width
			self.dimen.h = height
		end

		if self.use_top_radius then
			self:paintRoundedFrame(bb, x, y + top_offset, width, frame_height)
		elseif self.frame then
			if self.frame.dimen then
				self.frame.dimen.x = x
				self.frame.dimen.y = y + top_offset
				self.frame.dimen.w = width
				self.frame.dimen.h = frame_height
			end
			self.frame:paintTo(bb, x, y + top_offset)
		end

		if self.bottom_cover then
			local border_size = self.border_size or SIDE_TAB_BORDER_SIZE
			self.bottom_cover.dimen = Geom:new({
				x = x + border_size,
				y = y + top_offset + frame_height - border_size,
				w = math.max(1, width - 2 * border_size),
				h = border_size,
			})
			self.bottom_cover:paintTo(bb, x + border_size, y + top_offset + frame_height - border_size)
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
		card_shadow = nil,
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
		self:updateCardShadow()
		self.side_tab_widgets = {}
		self.side_tab_bounds = {}

		self.side_tab_position = nil
		self.tab_protrusion = self:useTabsMode() and math.max(0, TAB_TOUCH_HEIGHT - SIDE_TAB_BORDER_SIZE) or 0
		self.card_y = self.tab_protrusion
		self.dimen = Geom:new({
			x = 0,
			y = 0,
			w = self.screen_width,
			h = self.card_height + self.tab_protrusion,
		})

		self:buildCardPositions()
		self:buildVisibleCards()
		if self:useTabsMode() then
			self:buildSideTabs()
		end

		self:buildActiveContainer()
	end

	function CarouselRow:useTabsMode()
		return self.popup
			and self.popup.plugin
			and type(self.popup.plugin.useTabsMode) == "function"
			and self.popup.plugin:useTabsMode()
	end

	function CarouselRow:useCardShadows()
		return popupShowsCardShadows(self.popup)
	end

	function CarouselRow:updateCardShadow()
		local enabled = self:useCardShadows() and CARD_SHADOW_EXTENT > 0
		if enabled and not self.card_shadow then
			self.card_shadow = CardShadow:new({
				width = self.card_width,
				height = self.card_height,
			})
		elseif not enabled and self.card_shadow then
			self.card_shadow:free()
			self.card_shadow = nil
		end
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

		local height = TAB_TOUCH_HEIGHT
		local y = 0
		local card_radius = getPopupCardRadius(self.popup)
		local tab_radius = getRoundedTabRadius(card_radius)
		local available_width = math.max(1, self.card_width or 1)
		local x = active_x
		local specs = {}
		local used_width = 0

		for page_index = PAGE_DICTIONARY, PAGE_WIKIPEDIA do
			local active = page_index == self.active_index
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

		if used_width > available_width then
			local base_width = math.max(1, math.floor(available_width / #specs))
			used_width = 0
			for index, spec in ipairs(specs) do
				spec.width = index == #specs and math.max(1, available_width - base_width * (#specs - 1)) or base_width
				used_width = used_width + spec.width
			end
		end

		for _, spec in ipairs(specs) do
			self.side_tab_widgets[spec.page_index] = CardTabButton:new({
				text = spec.text,
				width = spec.width,
				height = height,
				active = spec.active,
				radius = tab_radius,
				show_parent = self.popup,
				callback = function()
					return self.popup.plugin:switchToPage(spec.page_index)
				end,
			})

			self.side_tab_bounds[spec.page_index] = Geom:new({
				x = x,
				y = y,
				w = spec.width,
				h = height,
			})
			x = x + spec.width
		end
	end

	function CarouselRow:paintSideTabs(bb, base_x, base_y)
		if not self:useTabsMode() then
			return
		end

		for page_index = PAGE_DICTIONARY, PAGE_WIKIPEDIA do
			local widget = self.side_tab_widgets and self.side_tab_widgets[page_index]
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

	function CarouselRow:paintActiveTabConnector(bb, base_x, base_y)
		if not self:useTabsMode() then
			return
		end

		local bounds = self.side_tab_bounds and self.side_tab_bounds[self.active_index]
		if not bounds then
			return
		end

		local active_tab = self.side_tab_widgets and self.side_tab_widgets[self.active_index]
		local active_tab_border_size = active_tab and active_tab.border_size or SIDE_TAB_BORDER_SIZE or 1
		local border_size = math.max(1, CARD_BORDER_SIZE or 1, active_tab_border_size)
		local card_radius = getPopupCardRadius(self.popup)
		local active_x = self.positions and self.positions[self.active_index]
		local card_x = (base_x or 0) + (active_x or bounds.x)
		local card_y = (base_y or 0) + (self.card_y or 0)
		local card_right = card_x + self.card_width

		local tab_left = (base_x or 0) + bounds.x
		local tab_right = tab_left + bounds.w
		local cover_x = math.max(card_x + border_size, tab_left + active_tab_border_size)
		local cover_right = math.min(card_right - border_size, tab_right - active_tab_border_size)
		local cover_width = math.max(1, cover_right - cover_x)

		self.active_tab_connector = self.active_tab_connector
			or LineWidget:new({
				background = Blitbuffer.COLOR_WHITE,
				dimen = Geom:new({ w = cover_width, h = border_size }),
			})
		self.active_tab_connector.dimen = Geom:new({
			x = cover_x,
			y = card_y,
			w = cover_width,
			h = border_size,
		})
		self.active_tab_connector:paintTo(bb, cover_x, card_y)

		if not card_radius or card_radius <= 0 then
			return
		end

		if self.active_index == PAGE_DICTIONARY then
			local bridge_height = math.max(border_size, math.min(card_radius, Screen:scaleBySize(5)))
			local bridge_x = cover_x
			local bridge_right = math.min(tab_right - active_tab_border_size, card_right - border_size)
			local bridge_width = math.max(1, bridge_right - bridge_x)

			self.active_tab_first_bridge = self.active_tab_first_bridge
				or LineWidget:new({
					background = Blitbuffer.COLOR_WHITE,
					dimen = Geom:new({ w = bridge_width, h = bridge_height }),
				})
			self.active_tab_first_bridge.dimen = Geom:new({
				x = bridge_x,
				y = card_y,
				w = bridge_width,
				h = bridge_height,
			})
			self.active_tab_first_bridge:paintTo(bb, bridge_x, card_y)
			return
		end

		local first_tab_bounds = self.side_tab_bounds and self.side_tab_bounds[PAGE_DICTIONARY]
		local left_join_x = first_tab_bounds and ((base_x or 0) + first_tab_bounds.x) or (card_x + border_size)
		local left_join_w = math.max(0, cover_x - left_join_x)
		if left_join_w > 0 then
			self.rounded_left_join_line = self.rounded_left_join_line
				or LineWidget:new({
					background = Blitbuffer.COLOR_BLACK,
					dimen = Geom:new({ w = left_join_w, h = border_size }),
				})
			self.rounded_left_join_line.dimen = Geom:new({
				x = left_join_x,
				y = card_y,
				w = left_join_w,
				h = border_size,
			})
			self.rounded_left_join_line:paintTo(bb, left_join_x, card_y)
		end
	end

	function CarouselRow:getSideTabPage(pos, row_y)
		if not self:useTabsMode() or type(pos) ~= "table" then
			return nil
		end

		for page_index = PAGE_DICTIONARY, PAGE_WIKIPEDIA do
			local bounds = self.side_tab_bounds and self.side_tab_bounds[page_index]
			if bounds then
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
		end

		return nil
	end

	function CarouselRow:getSize()
		return self.dimen
	end

	function CarouselRow:getActiveCardDimen(row_y)
		local card_x = self.positions and self.positions[self.active_index]
		if not card_x then
			card_x = math.floor(((self.screen_width or Screen:getWidth()) - (self.card_width or 0)) / 2)
		end

		local shadow_extent = self:useCardShadows() and CARD_SHADOW_EXTENT or 0
		return Geom:new({
			x = card_x,
			y = (row_y or 0) + (self.card_y or 0),
			w = (self.card_width or 1) + shadow_extent,
			h = (self.card_height or 1) + shadow_extent,
		})
	end

	function CarouselRow:getActiveCardContentDimen(row_y)
		local card_x = self.positions and self.positions[self.active_index]
		if not card_x then
			card_x = math.floor(((self.screen_width or Screen:getWidth()) - (self.card_width or 0)) / 2)
		end

		local card_y = (row_y or 0) + (self.card_y or 0)
		local top_offset = CARD_BORDER_SIZE + CARD_PADDING_TOP
		local bottom_offset = CARD_BORDER_SIZE + CARD_PADDING_BOTTOM
		return Geom:new({
			x = card_x + CARD_BORDER_SIZE,
			y = card_y + top_offset,
			w = math.max(1, (self.card_width or 1) - 2 * CARD_BORDER_SIZE),
			h = math.max(1, (self.card_height or 1) - top_offset - bottom_offset),
		})
	end

	function CarouselRow:paintCardShadow(bb, base_x, base_y, index)
		if not self:useCardShadows() or CARD_SHADOW_EXTENT <= 0 then
			return
		end

		local card_x = self.positions and self.positions[index]
		if not self.card_shadow or not card_x then
			return
		end

		local x = (base_x or 0) + card_x
		local y = (base_y or 0) + (self.card_y or 0)
		self.card_shadow:paintTo(bb, x, y)
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

		if self:useTabsMode() then
			self:paintSideTabs(bb, x, y)
			self:paintActiveTabConnector(bb, x, y)
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
		self.side_tab_widgets = {}
		self.side_tab_bounds = {}
		self.active_card = nil
		self.active_container = nil
		self:updateCardShadow()

		self.tab_protrusion = self:useTabsMode() and math.max(0, TAB_TOUCH_HEIGHT - SIDE_TAB_BORDER_SIZE) or 0
		self.card_y = self.tab_protrusion
		if self.dimen then
			self.dimen.h = self.card_height + self.tab_protrusion
		end

		self:buildCardPositions()
		self:buildVisibleCards()
		if self:useTabsMode() then
			self:buildSideTabs()
		end

		self:buildActiveContainer()
		return true
	end

	function CarouselRow:free(...)
		if self.card_shadow then
			self.card_shadow:free()
			self.card_shadow = nil
		end
		WidgetContainer.free(self, ...)
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

	function LookupPreviewPopup:showCardShadows()
		return popupShowsCardShadows(self)
	end

	function LookupPreviewPopup:getCardDimensions(card_width, card_height, header, buttons, page_type)
		local header_height = getWidgetSize(header).h or Screen:scaleBySize(46)
		local button_height = page_type == PAGE_TRANSLATION and TRANSLATION_BUTTON_HEIGHT or DICTIONARY_BUTTON_HEIGHT
		local button_gap = page_type == PAGE_TRANSLATION and TRANSLATION_BUTTON_GAP or DICTIONARY_BUTTON_GAP
		local buttons_height = buttons and (getWidgetSize(buttons).h or button_height) or 0
		local buttons_gap = buttons and button_gap or 0
		local html_height = math.max(
			MIN_HTML_HEIGHT,
			card_height
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
		local header = self:makeHeader(payload, content_width)
		local buttons = self:makeDictionaryButtons(payload, content_width)
		local html_height, buttons_gap =
			self:getCardDimensions(card_width, card_height, header, buttons, payload.page_type)

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

		local card_radius = self:getCardRadius()
		return LookupCardFrame:new({
			background = Blitbuffer.COLOR_WHITE,
			bordersize = CARD_BORDER_SIZE,
			color = CARD_BORDER_COLOR,
			radius = card_radius,
			square_top_left = self:useTabsMode() and card_radius ~= nil and card_radius > 0,
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

		local tab_protrusion = self:useTabsMode() and math.max(0, TAB_TOUCH_HEIGHT - SIDE_TAB_BORDER_SIZE) or 0
		local shadow_extent = self:showCardShadows() and CARD_SHADOW_EXTENT or 0
		self.anchor_top = self:shouldAnchorTop(card_height + tab_protrusion + shadow_extent)
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
			y = screen_height - CARD_EDGE_MARGIN - row_height - shadow_extent
			self[1] = BottomContainer:new({
				dimen = Screen:getSize(),
				VerticalGroup:new({
					row,
					VerticalSpan:new({ width = CARD_EDGE_MARGIN + shadow_extent }),
				}),
			})
		end

		local visible_height = row_height + shadow_extent
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

	function LookupPreviewPopup:getActiveCardDirtyDimen()
		local row_y = self.visible_dimen and self.visible_dimen.y or 0
		if self.card_container and self.card_container.getActiveCardDimen then
			return self.card_container:getActiveCardDimen(row_y)
		end
		return self.visible_dimen or Screen:getSize()
	end

	function LookupPreviewPopup:getActiveCardContentDirtyDimen()
		local row_y = self.visible_dimen and self.visible_dimen.y or 0
		if self.card_container and self.card_container.getActiveCardContentDimen then
			return self.card_container:getActiveCardContentDimen(row_y)
		end
		return self:getActiveCardDirtyDimen()
	end

	function LookupPreviewPopup:markDirty(mode, dimen)
		local dirty_mode = mode or "ui"
		local dirty_dimen = dimen or self.visible_dimen or Screen:getSize()
		UIManager:setDirty(self.dialog or self, function()
			return dirty_mode, dirty_dimen
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
			self:markDirty("partial", self:getActiveCardContentDirtyDimen())
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

		return false
	end

	function LookupPreviewPopup:onNextPage()
		return self.plugin:switchToPage(math.min(PAGE_WIKIPEDIA, self.active_index + 1))
	end

	function LookupPreviewPopup:onPrevPage()
		return self.plugin:switchToPage(math.max(PAGE_DICTIONARY, self.active_index - 1))
	end
end
