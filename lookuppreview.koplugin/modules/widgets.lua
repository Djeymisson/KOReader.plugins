-- Lookup Preview module: widgets.
-- Auto-split from the original main.lua; loaded by main.lua.
return function(ctx)
    setmetatable(ctx, { __index = _G })
    setfenv(1, ctx)


HeaderSubtitleButton = InputContainer:extend({
	text = nil,
	face = nil,
	width = nil,
	height = nil,
	callback = nil,
	show_parent = nil,
})

function HeaderSubtitleButton:init()
	local outer_w = self.width or Screen:scaleBySize(240)
	local label = TextWidget:new({
		text = self.text or "",
		face = self.face or SUBTITLE_FACE,
		max_width = outer_w,
	})
	local label_size = getWidgetSize(label)
	local outer_h = self.height or math.max(1, label_size.h or Screen:scaleBySize(14))

	self.frame = FrameContainer:new({
		show_parent = self.show_parent,
		bordersize = 0,
		background = Blitbuffer.COLOR_WHITE,
		padding = 0,
		label,
	})

	self.dimen = Geom:new({ x = 0, y = 0, w = outer_w, h = outer_h })
	self[1] = self.frame
	self.ges_events = {
		TapHeaderSubtitle = {
			GestureRange:new({
				ges = "tap",
				range = self.dimen,
			}),
		},
	}
end

function HeaderSubtitleButton:onTapHeaderSubtitle()
	if self.callback then
		return self.callback()
	end
	return true
end

HeaderPageButton = InputContainer:extend({
	text = nil,
	width = nil,
	callback = nil,
	show_parent = nil,
})

function HeaderPageButton:init()
	local outer_w = self.width or HEADER_MENU_WIDTH
	local label = TextWidget:new({
		text = self.text or "",
		face = HEADER_BUTTON_FACE,
		bold = true,
		max_width = math.max(1, outer_w - 2 * HEADER_MENU_PADDING_H),
	})

	self.frame = FrameContainer:new({
		show_parent = self.show_parent,
		bordersize = 0,
		background = Blitbuffer.COLOR_WHITE,
		padding_left = HEADER_MENU_PADDING_H,
		padding_right = HEADER_MENU_PADDING_H,
		padding_top = HEADER_MENU_PADDING_V,
		padding_bottom = HEADER_MENU_PADDING_V,
		CenterContainer:new({
			dimen = Geom:new({
				w = math.max(1, outer_w - 2 * HEADER_MENU_PADDING_H),
				h = math.max(1, HEADER_MENU_HEIGHT - 2 * HEADER_MENU_PADDING_V),
			}),
			label,
		}),
	})

	self.dimen = Geom:new({
		x = 0,
		y = 0,
		w = outer_w,
		h = HEADER_MENU_HEIGHT,
	})
	self[1] = self.frame

	self.ges_events = {
		TapHeaderPageMenu = {
			GestureRange:new({
				ges = "tap",
				range = self.dimen,
			}),
		},
	}
end

function HeaderPageButton:onTapHeaderPageMenu()
	if self.callback then
		return self.callback()
	end
	return true
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

function DictionaryCardButton:init()
	local outer_w = self.width or Screen:scaleBySize(64)
	local outer_h = self.height or DICTIONARY_BUTTON_HEIGHT
	local padding_h = math.max(1, math.floor(Size.padding.button * 0.55))
	local padding_v = math.max(0, math.floor(Size.padding.button * 0.25))
	local inner_w = math.max(1, outer_w - 2 * padding_h)
	local inner_h = math.max(1, outer_h - 2 * padding_v)
	local label

	if self.icon_file then
		label = IconWidget:new({
			file = self.icon_file,
			width = self.icon_width,
			height = self.icon_height,
			alpha = true,
			is_icon = true,
		})
	elseif self.icon then
		label = IconWidget:new({
			icon = self.icon,
			width = self.icon_width,
			height = self.icon_height,
			alpha = true,
		})
	else
		label = TextWidget:new({
			text = self.text or "",
			face = DICTIONARY_BUTTON_FACE,
			bold = true,
			max_width = inner_w,
		})
	end

	self.frame = FrameContainer:new({
		show_parent = self.show_parent,
		bordersize = 0,
		background = Blitbuffer.COLOR_WHITE,
		padding_left = padding_h,
		padding_right = padding_h,
		padding_top = padding_v,
		padding_bottom = padding_v,
		CenterContainer:new({
			dimen = Geom:new({ w = inner_w, h = inner_h }),
			label,
		}),
	})

	self.dimen = Geom:new({ x = 0, y = 0, w = outer_w, h = outer_h })
	self[1] = self.frame
	self.ges_events = {
		TapDictionaryButton = {
			GestureRange:new({
				ges = "tap",
				range = self.dimen,
			}),
		},
	}
end

function DictionaryCardButton:onTapDictionaryButton()
	if self.callback then
		return self.callback()
	end
	return true
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
	local label = TextWidget:new({
		text = (is_active and "• " or "  ") .. PAGE_TITLES[page_index],
		face = HEADER_MENU_FACE,
		bold = is_active,
		max_width = math.max(1, width - 2 * PAGE_MENU_PADDING_H),
	})

	return LeftContainer:new({
		allow_mirroring = false,
		dimen = Geom:new({
			w = width,
			h = PAGE_MENU_ITEM_HEIGHT,
		}),
		HorizontalGroup:new({
			HorizontalSpan:new({ width = PAGE_MENU_PADDING_H }),
			label,
		}),
	})
end

function SimplePageMenu:init()
	local screen_width = Screen:getWidth()
	local screen_height = Screen:getHeight()
	local parent = self.parent_popup
	local parent_dimen = parent and parent.visible_dimen
	local anchor = self.anchor_dimen
	local border_size = Size.border.thin
	local content_width = math.min(PAGE_MENU_WIDTH, screen_width - 2 * CARD_EDGE_MARGIN - 2 * border_size)

	self.container = FrameContainer:new({
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

	local container_size = getWidgetSize(self.container)
	local width = container_size.w and container_size.w > 0 and container_size.w or (content_width + 2 * border_size)
	local height = container_size.h and container_size.h > 0 and container_size.h
		or (PAGE_MENU_ITEM_HEIGHT * 3 + 2 * border_size)
	local x
	local y

	if anchor then
		x = anchor.x + anchor.w - width
	else
		x = math.floor((screen_width - width) / 2)
	end

	local min_x = CARD_EDGE_MARGIN
	local max_x = screen_width - width - CARD_EDGE_MARGIN
	x = math.max(min_x, math.min(max_x, x))

	if anchor then
		-- Keep the selector over the active card instead of placing it above
		-- the popup on top of the reader page.
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
			y = math.max(min_y, math.min(max_y, y))
		else
			y = math.max(CARD_EDGE_MARGIN, math.min(screen_height - height - CARD_EDGE_MARGIN, y))
		end
	else
		y = math.max(CARD_EDGE_MARGIN, math.min(screen_height - height - CARD_EDGE_MARGIN, y))
	end

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
		self.ges_events = {
			TapPageMenu = {
				GestureRange:new({
					ges = "tap",
					range = self.dimen,
				}),
			},
		}
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

	local relative_y = ges.pos.y - self.visible_dimen.y
	local item_index = math.floor(relative_y / PAGE_MENU_ITEM_HEIGHT) + 1
	local page_index = PAGE_DICTIONARY
	if item_index == 2 then
		page_index = PAGE_TRANSLATION
	elseif item_index >= 3 then
		page_index = PAGE_WIKIPEDIA
	end

	local parent = self.parent_popup
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
})

function CarouselRow:init()
	self.screen_width = self.screen_width or Screen:getWidth()
	self.card_width = self.card_width or math.floor(self.screen_width * CARD_WIDTH_RATIO)
	self.card_height = self.card_height or math.floor(Screen:getHeight() * CARD_HEIGHT_RATIO)
	self.active_index = self.active_index or PAGE_DICTIONARY
	self.dimen = Geom:new({ x = 0, y = 0, w = self.screen_width, h = self.card_height })
	self.cards = {}
	self.shadow_widgets = {}

	local popup = self.popup
	if popup then
		for index = PAGE_DICTIONARY, PAGE_WIKIPEDIA do
			if math.abs(index - self.active_index) <= 1 then
				local payload = popup.plugin:getPagePayload(popup.state, index, index == self.active_index)
				local card = popup:makeCard(payload, self.card_width, self.card_height)
				self.cards[index] = card

				if CARD_SHADOW_ENABLED and CARD_SHADOW_OFFSET > 0 then
					self.shadow_widgets[index] = LineWidget:new({
						background = CARD_SHADOW_COLOR,
						dimen = Geom:new({ w = self.card_width, h = self.card_height }),
					})
				end

				if index == self.active_index then
					self.active_card = card
				end
			end
		end
	end

	local active_x = math.floor((self.screen_width - self.card_width) / 2)
	self.positions = {
		[self.active_index - 1] = active_x - self.card_width - CARD_GAP,
		[self.active_index] = active_x,
		[self.active_index + 1] = active_x + self.card_width + CARD_GAP,
	}

	-- The centered card must also be part of the widget tree, otherwise
	-- widgets inside it (notably ScrollHtmlWidget) are painted but don't
	-- reliably receive touch/pan events.
	if self.active_card then
		self.active_container = CenterContainer:new({
			dimen = self.dimen,
			self.active_card,
		})
		self[1] = self.active_container
	end
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
	local y = (base_y or 0) + CARD_SHADOW_OFFSET

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
	local y = base_y or 0

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

	-- Draw side cards first. They keep their full size and are simply clipped
	-- by the screen edge. The active card is painted through active_container
	-- so it remains a real child widget and can handle scrolling.
	self:paintCard(bb, x, y, self.active_index - 1)
	self:paintCard(bb, x, y, self.active_index + 1)

	if self.active_container then
		self:paintCardShadow(bb, x, y, self.active_index)
		self.active_container:paintTo(bb, x, y)
	else
		self:paintCard(bb, x, y, self.active_index)
	end
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

function LookupPreviewPopup:makeHeader(payload, content_width)
	local menu_button = HeaderPageButton:new({
		text = "☰",
		width = HEADER_MENU_WIDTH,
		show_parent = self,
		callback = function()
			return self:showPageMenu()
		end,
	})

	local menu_width = HEADER_MENU_WIDTH
	local text_width = math.max(1, content_width - menu_width - HEADER_TITLE_MENU_GAP)

	local function makeLeftText(text, face, bold, callback)
		local widget
		if callback then
			widget = HeaderSubtitleButton:new({
				text = text or EMPTY_TEXT,
				face = face,
				width = text_width,
				show_parent = self,
				callback = callback,
			})
		else
			widget = TextWidget:new({
				text = text or EMPTY_TEXT,
				face = face,
				bold = bold and true or false,
				max_width = text_width,
			})
		end
		local size = getWidgetSize(widget)
		return LeftContainer:new({
			allow_mirroring = false,
			dimen = Geom:new({
				w = text_width,
				h = math.max(1, size.h or Screen:scaleBySize(14)),
			}),
			widget,
		})
	end

	local text_items = {
		makeLeftText(payload.title or EMPTY_TEXT, TITLE_FACE, true),
	}

	if payload.subtitle and payload.subtitle ~= "" then
		text_items[#text_items + 1] = VerticalSpan:new({ width = HEADER_GAP })
		text_items[#text_items + 1] = makeLeftText(payload.subtitle, SUBTITLE_FACE, false, payload.subtitle_callback)
	end

	local text_block = VerticalGroup:new(text_items)
	local text_height = getWidgetSize(text_block).h or Screen:scaleBySize(24)
	local menu_height = getWidgetSize(menu_button).h or HEADER_MENU_HEIGHT
	local row_height = math.max(text_height, menu_height)

	local items = {
		HorizontalGroup:new({
			LeftContainer:new({
				allow_mirroring = false,
				dimen = Geom:new({ w = text_width, h = row_height }),
				text_block,
			}),
			HorizontalSpan:new({ width = HEADER_TITLE_MENU_GAP }),
			CenterContainer:new({
				dimen = Geom:new({ w = menu_width, h = row_height }),
				menu_button,
			}),
		}),
		VerticalSpan:new({ width = HEADER_SEPARATOR_GAP }),
		LineWidget:new({
			background = Blitbuffer.COLOR_GRAY,
			dimen = Geom:new({ w = content_width, h = math.max(1, Screen:scaleBySize(1)) }),
		}),
		VerticalSpan:new({ width = HEADER_SEPARATOR_GAP }),
	}

	return VerticalGroup:new(items)
end

function LookupPreviewPopup:makeDictionaryButtons(payload, content_width)
	local button_specs = payload and (payload.card_buttons or payload.dictionary_buttons)
	if type(button_specs) ~= "table" or #button_specs == 0 then
		return nil
	end

	local separator_count = math.max(0, #button_specs - 1)
	local available_width = math.max(1, content_width - DICTIONARY_BUTTON_SEPARATOR_WIDTH * separator_count)
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

	local used_width = 0
	local widgets = {}
	for index, item in ipairs(button_specs) do
		if index > 1 then
			widgets[#widgets + 1] = LineWidget:new({
				background = Blitbuffer.COLOR_GRAY,
				dimen = Geom:new({
					w = DICTIONARY_BUTTON_SEPARATOR_WIDTH,
					h = DICTIONARY_BUTTON_HEIGHT,
				}),
			})
		end

		local button_width
		if index == #button_specs then
			button_width = math.max(1, available_width - used_width)
		else
			button_width = math.max(1, math.floor(available_width * weights[index] / total_weight))
			used_width = used_width + button_width
		end

		local spec = item.spec or {}
		widgets[#widgets + 1] = DictionaryCardButton:new({
			text = spec.text,
			icon = spec.icon,
			icon_file = spec.icon_file,
			width = button_width,
			height = DICTIONARY_BUTTON_HEIGHT,
			icon_width = DICTIONARY_ICON_SIZE,
			icon_height = DICTIONARY_ICON_SIZE,
			show_parent = self,
			callback = item.callback,
		})
	end

	return HorizontalGroup:new(widgets)
end

function LookupPreviewPopup:makeCard(payload, card_width, card_height)
	local content_width = math.max(1, card_width - 2 * CARD_PADDING_H - 2 * CARD_BORDER_SIZE)
	local header = self:makeHeader(payload, content_width)
	local header_height = getWidgetSize(header).h or Screen:scaleBySize(46)
	local dictionary_buttons = self:makeDictionaryButtons(payload, content_width)
	local action_button_height = payload and payload.page_type == PAGE_TRANSLATION and TRANSLATION_BUTTON_HEIGHT
		or DICTIONARY_BUTTON_HEIGHT
	local action_button_gap = payload and payload.page_type == PAGE_TRANSLATION and TRANSLATION_BUTTON_GAP
		or DICTIONARY_BUTTON_GAP
	local dictionary_buttons_height = dictionary_buttons
			and (getWidgetSize(dictionary_buttons).h or action_button_height)
		or 0
	local dictionary_buttons_gap = dictionary_buttons and action_button_gap or 0
	local html_height = math.max(
		MIN_HTML_HEIGHT,
		card_height
			- header_height
			- dictionary_buttons_height
			- dictionary_buttons_gap
			- CARD_PADDING_TOP
			- CARD_PADDING_BOTTOM
			- 2 * CARD_BORDER_SIZE
	)

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
		HorizontalGroup:new({
			HorizontalSpan:new({ width = CARD_PADDING_H }),
			header,
			HorizontalSpan:new({ width = CARD_PADDING_H }),
		}),
		HorizontalGroup:new({
			HorizontalSpan:new({ width = CARD_PADDING_H }),
			html_widget,
			HorizontalSpan:new({ width = CARD_PADDING_H }),
		}),
	}

	if dictionary_buttons then
		content_items[#content_items + 1] = VerticalSpan:new({ width = dictionary_buttons_gap })
		content_items[#content_items + 1] = HorizontalGroup:new({
			HorizontalSpan:new({ width = CARD_PADDING_H }),
			dictionary_buttons,
			HorizontalSpan:new({ width = CARD_PADDING_H }),
		})
	end

	content_items[#content_items + 1] = VerticalSpan:new({ width = CARD_PADDING_BOTTOM })

	local content = VerticalGroup:new(content_items)

	local card = FrameContainer:new({
		background = Blitbuffer.COLOR_WHITE,
		bordersize = CARD_BORDER_SIZE,
		color = CARD_BORDER_COLOR,
		radius = CARD_RADIUS,
		margin = 0,
		padding = 0,
		content,
	})

	return card, Geom:new({ w = card_width, h = card_height })
end

function LookupPreviewPopup:makeRow(card_width, card_height)
	local row = CarouselRow:new({
		popup = self,
		active_index = self.active_index or PAGE_DICTIONARY,
		screen_width = Screen:getWidth(),
		card_width = card_width,
		card_height = card_height,
	})

	return row, card_height
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

	local row, row_height = self:makeRow(card_width, card_height)
	self.card_container = row
	self.anchor_top = self:shouldAnchorTop(row_height)

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
	local x = active_x + CARD_BORDER_SIZE + CARD_PADDING_H + content_width - HEADER_MENU_WIDTH
	local y = ((self.visible_dimen and self.visible_dimen.y) or CARD_EDGE_MARGIN) + CARD_BORDER_SIZE + CARD_PADDING_TOP

	return Geom:new({
		x = x,
		y = y,
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
	if ges and ges.pos and self.visible_dimen and ges.pos:notIntersectWith(self.visible_dimen) then
		return self:onClose()
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

	-- Do not close on vertical swipes. Vertical movement must remain available
	-- to ScrollHtmlWidget so dictionary/translation/Wikipedia content can scroll.
	return false
end

function LookupPreviewPopup:onNextPage()
	return self.plugin:switchToPage(math.min(PAGE_WIKIPEDIA, self.active_index + 1))
end

function LookupPreviewPopup:onPrevPage()
	return self.plugin:switchToPage(math.max(PAGE_DICTIONARY, self.active_index - 1))
end


end
