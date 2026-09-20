-- Tests of modules/fitmodel.lua, which is plain Lua and needs
-- no KOReader. Run with run.sh (unit), or:
--   DE_PLUGIN=/path/to/dictionaryexplorer.koplugin luajit fitmodel_test.lua

local plugin = assert(os.getenv("DE_PLUGIN"), "set DE_PLUGIN to the plugin folder")
local FitModel = dofile(plugin .. "/modules/fitmodel.lua")

local passed, failed = 0, 0
local function check(name, ok, detail)
	if ok then
		passed = passed + 1
	else
		failed = failed + 1
	end
	print(string.format("%s  %s%s", ok and "PASS" or "FAIL", name, detail and (" -- " .. detail) or ""))
end

-- A model of a dictionary where an entry costs true_a pixels plus true_c per
-- byte, fed `samples` noisy measurements; returns the mean relative error of
-- its predictions over the first 3 and over the last 5 measurements.
local function learn(true_a, true_c, prior_a, prior_c, noise, samples)
	math.randomseed(7)
	local model = FitModel.new(prior_a, prior_c)
	local errors = {}
	for index = 1, samples do
		local entries = math.random(2, 14)
		local bytes = math.random(60, 400) * entries -- bytes and entries grow together, as in real pages
		local truth = true_a * entries + true_c * bytes
		if index > 1 then
			errors[#errors + 1] = math.abs(model:predict(entries, bytes) - truth) / truth
		end
		model:add(entries, bytes, truth * (1 + (math.random() - 0.5) * 2 * noise))
	end
	local early = (errors[1] + errors[2] + errors[3]) / 3
	local late = 0
	for index = #errors - 4, #errors do
		late = late + errors[index]
	end
	return model, early, late / 5
end

-- Whatever the starting point, 30 measurements bring the predictions to within a few percent.
for _index, case in ipairs({
	{ name = "prior 2x too low on text", a = 40, c = 0.10, pa = 65, pc = 0.05, noise = 0.03 },
	{ name = "markup-heavy dictionary (prior 4x off)", a = 25, c = 0.22, pa = 65, pc = 0.05, noise = 0.03 },
	{ name = "almost no text per entry", a = 60, c = 0.02, pa = 65, pc = 0.05, noise = 0.03 },
	{ name = "noisy measurements (10%)", a = 40, c = 0.10, pa = 65, pc = 0.05, noise = 0.10 },
	{ name = "perfect prior", a = 40, c = 0.10, pa = 40, pc = 0.10, noise = 0.03 },
}) do
	local _, early, late = learn(case.a, case.c, case.pa, case.pc, case.noise, 30)
	check("converges: " .. case.name, late < 0.03, string.format("error %.1f%% -> %.1f%%", early * 100, late * 100))
end

-- Entries and bytes exactly proportional (a degenerate fit): stay finite and near the prior.
local degenerate = FitModel.new(65, 0.05)
for index = 1, 10 do
	degenerate:add(5, 500, 400 + index)
end
check(
	"degenerate data keeps the model finite",
	degenerate.per_entry == degenerate.per_entry and degenerate.per_byte == degenerate.per_byte and degenerate.per_entry > 0 and degenerate.per_byte > 0
)

-- Measurements that make no sense are ignored.
local ignoring = FitModel.new(65, 0.05)
ignoring:add(0, 10, 5)
ignoring:add(3, 10, 0)
ignoring:add(-1, 10, 5)
check("empty or non-positive measurements are ignored", #ignoring.samples == 0)

-- The fitted values stay within reach of the prior, however wild the data.
local wild = FitModel.new(65, 0.05)
for _index = 1, 40 do
	wild:add(3, 300, 100000)
end
check("fitted values are clamped near the prior", wild.per_entry <= 5 * 65 and wild.per_byte <= 5 * 0.05)

-- The ring of measurements keeps only the most recent ones.
local ring = FitModel.new(65, 0.05)
for index = 1, 100 do
	ring:add(index % 7 + 1, 300, 500)
end
check("only the latest measurements are kept", #ring.samples == 24, #ring.samples .. " samples")

print(string.format("\nRESULT passed=%d failed=%d", passed, failed))
os.exit(failed == 0 and 0 or 1)
