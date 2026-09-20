--[[
Predicts how tall a run of dictionary entries is once laid out.

Laying a page out is the most expensive thing the viewer does, and how many
entries fit on a screen depends on the dictionary (how much markup its text
carries), the font and the width. Instead of trying several run lengths until
one fits, the viewer asks this model for a good first guess and teaches it the
real heights it measures, so that the guess gets closer with every page.

The model is  height = per_entry * entries + per_byte * bytes,  fitted by least
squares to the most recent measurements. Two pseudo-measurements pull it
towards a prior (worked out from the font and the width), less and less as
measurements come in, so the very first pages are still reasonable.
]]

local MAX_SAMPLES = 24
-- Keeps the fitted values within reach of the prior, whatever the data says.
local LOWEST, HIGHEST = 0.2, 5
-- Size of the two pseudo-measurements carrying the prior: about a page of
-- entries with no text, and about a page of text with no per-entry overhead.
local PRIOR_ENTRIES, PRIOR_BYTES = 8, 2000

local FitModel = {}
FitModel.__index = FitModel

--- @number per_entry prior height of an entry's fixed part (rule, heading), in pixels
-- @number per_byte prior height of one byte of definition, in pixels
function FitModel.new(per_entry, per_byte)
	return setmetatable({
		prior_entry = per_entry,
		prior_byte = per_byte,
		per_entry = per_entry,
		per_byte = per_byte,
		samples = {},
		next_slot = 1,
	}, FitModel)
end

local function clamp(value, prior)
	return math.min(math.max(value, LOWEST * prior), HIGHEST * prior)
end

function FitModel:_fit()
	local entry_prior, byte_prior = self.prior_entry, self.prior_byte
	-- The prior matters less with each measurement: entries and bytes tend to
	-- grow together, and a prior that kept its weight would keep dragging the
	-- fit away from what was measured.
	local weight = 1 / (1 + #self.samples)
	local nn = weight * PRIOR_ENTRIES * PRIOR_ENTRIES
	local bb = weight * PRIOR_BYTES * PRIOR_BYTES
	local nb = 0
	local nu = nn * entry_prior
	local bu = bb * byte_prior
	for _index, sample in ipairs(self.samples) do
		local entries, bytes, height = sample[1], sample[2], sample[3]
		nn = nn + entries * entries
		nb = nb + entries * bytes
		bb = bb + bytes * bytes
		nu = nu + entries * height
		bu = bu + bytes * height
	end
	local determinant = nn * bb - nb * nb
	if determinant <= 1e-9 * nn * bb then
		return -- entries and bytes moved together: keep the current values
	end
	self.per_entry = clamp((nu * bb - nb * bu) / determinant, entry_prior)
	self.per_byte = clamp((nn * bu - nb * nu) / determinant, byte_prior)
end

--- Records that `entries` entries with `bytes` bytes of definitions took `height` pixels.
function FitModel:add(entries, bytes, height)
	if entries <= 0 or height <= 0 then
		return
	end
	self.samples[self.next_slot] = { entries, bytes, height }
	self.next_slot = self.next_slot % MAX_SAMPLES + 1
	self:_fit()
end

--- Predicted height, in pixels, of a run.
function FitModel:predict(entries, bytes)
	return self.per_entry * entries + self.per_byte * bytes
end

return FitModel
