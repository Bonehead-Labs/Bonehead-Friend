-- Build `bonehead_face.aseprite` from the hand-drawn expression PNGs.
--
--   Aseprite.exe --batch \
--     --script-param dir=<abs art\src\faces> --script-param out=<abs.aseprite> \
--     --script-param names=neutral,happy,blissful,... --script-param cell=96 \
--     --script <abs>\_build_faces.lua
--
-- One frame per expression, each with its own single-frame tag, so Godot gets an
-- AnimatedSprite2D whose "animation" is simply which face he is wearing. The buddy then
-- picks an expression and a body animation independently, which is the whole point of
-- keeping the face off the body (docs/architecture.md).
--
-- The face never goes through the generator: two-pixel eyes do not survive it.

local dir = app.params["dir"]
local outPath = app.params["out"]
local names = app.params["names"]
local cell = tonumber(app.params["cell"] or "96")

if not dir or not outPath or not names then
	print("ERROR: need --script-param dir=<folder> out=<aseprite> names=<a,b,c>")
	return
end

local list = {}
for name in string.gmatch(names, "([^,]+)") do
	list[#list + 1] = name
end
print("building " .. #list .. " expressions")

local sprite = Sprite(cell, cell, ColorMode.RGB)
local layer = sprite.layers[1]
layer.name = "face"

for i, name in ipairs(list) do
	local path = dir .. "\\bonehead_face_" .. name .. ".png"
	local src = app.open(path)
	if not src then
		print("ERROR: could not open " .. path)
		return
	end
	local img = Image(cell, cell, ColorMode.RGB)
	img:drawSprite(src, 1)
	src:close()
	app.activeSprite = sprite

	-- A fresh Sprite() already owns frame 1, so the first expression fills it rather than
	-- appending after a blank.
	local frameNumber = i
	if i > 1 then
		frameNumber = sprite:newFrame().frameNumber
	end
	sprite:newCel(layer, frameNumber, img, Point(0, 0))

	local tag = sprite:newTag(frameNumber, frameNumber)
	tag.name = name
	tag.aniDir = AniDir.FORWARD
end

sprite:saveAs(outPath)
print("wrote " .. outPath .. ": " .. #sprite.frames .. " frames, " .. #sprite.tags .. " tags")
