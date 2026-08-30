-- Build `bonehead.aseprite` from every generated animation sheet, in one pass.
--
--   Aseprite.exe --batch \
--     --script-param dir=<abs art\raw> --script-param out=<abs.aseprite> \
--     --script-param cell=96 \
--     --script-param spec=idle:10,idle_sad:7,hurt:16,... \
--     --script <abs>\_build_body.lua
--
-- `spec` is `tag:fps` pairs; each reads `<dir>\body_<tag>.png`.
--
-- **One pass, and every tag created only after every frame exists.** Building this
-- incrementally does not work: `Sprite:newFrame()` appends at the end, and Aseprite extends
-- any tag whose range already ends at the last frame. Adding nine animations one at a time
-- therefore left all nine tags ending at frame 74 — `idle` reported 74 frames instead of 8,
-- and Godot played the entire file for every animation. The tags looked right at the moment
-- each was created and were silently stretched by the next append.
--
-- Tag names become Godot animation names through Aseprite Wizard, so they must match the
-- state names in docs/architecture.md.

local dir = app.params["dir"]
local outPath = app.params["out"]
local spec = app.params["spec"]
local cell = tonumber(app.params["cell"] or "96")

if not dir or not outPath or not spec then
	print("ERROR: need --script-param dir=<folder> out=<aseprite> spec=<tag:fps,...>")
	return
end

-- --- parse the spec ---------------------------------------------------------

local entries = {}
for pair in string.gmatch(spec, "([^,]+)") do
	local tag, fps = string.match(pair, "([^:]+):([%d%.]+)")
	if not tag then
		print("ERROR: bad spec entry '" .. pair .. "', want tag:fps")
		return
	end
	entries[#entries + 1] = { tag = tag, fps = tonumber(fps) }
end

-- --- read every sheet before touching the target ----------------------------

local function readSheet(path)
	local sheet = app.open(path)
	if not sheet then
		print("ERROR: could not open " .. path)
		return nil
	end
	app.activeSprite = sheet
	-- ROWS, not HORIZONTAL: an 8-frame animation comes back as a 4x2 grid and HORIZONTAL
	-- would read only the top row, silently dropping half the animation.
	app.command.ImportSpriteSheet {
		ui = false,
		type = SpriteSheetType.ROWS,
		frameBounds = Rectangle(0, 0, cell, cell),
	}
	local out = {}
	for i = 1, #sheet.frames do
		local img = Image(cell, cell, ColorMode.RGB)
		img:drawSprite(sheet, i)
		out[#out + 1] = img
	end
	sheet:close()
	return out
end

for _, e in ipairs(entries) do
	e.frames = readSheet(dir .. "\\body_" .. e.tag .. ".png")
	if not e.frames then return end
end

-- --- all frames first -------------------------------------------------------

local sprite = Sprite(cell, cell, ColorMode.RGB)
local layer = sprite.layers[1]
layer.name = "body"

local cursor = 1
for _, e in ipairs(entries) do
	e.from = cursor
	for i, img in ipairs(e.frames) do
		-- Frame 1 already exists on a fresh Sprite(); fill it rather than appending past it.
		local frameNumber = cursor
		if cursor > 1 then
			frameNumber = sprite:newFrame().frameNumber
		end
		sprite:newCel(layer, frameNumber, img, Point(0, 0))
		sprite.frames[frameNumber].duration = 1.0 / e.fps
		cursor = cursor + 1
	end
	e.to = cursor - 1
end

-- --- then every tag ---------------------------------------------------------

for _, e in ipairs(entries) do
	local tag = sprite:newTag(e.from, e.to)
	tag.name = e.tag
	tag.aniDir = AniDir.FORWARD
end

sprite:saveAs(outPath)
print("wrote " .. outPath .. ": " .. #sprite.frames .. " frames, " .. #sprite.tags .. " tags")
for _, t in ipairs(sprite.tags) do
	print(string.format("  %-12s %d..%d (%d frames)", t.name,
		t.fromFrame.frameNumber, t.toFrame.frameNumber,
		t.toFrame.frameNumber - t.fromFrame.frameNumber + 1))
end
