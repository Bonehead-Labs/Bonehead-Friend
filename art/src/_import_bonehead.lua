-- One-off: convert the prototype's 320x64 idle strip into a tagged .aseprite source.
-- Run headless:
--   Aseprite.exe --batch --script-param in=<abs> --script-param out=<abs> --script this.lua
--
-- Paths come through --script-param, NOT environment variables: Aseprite is a Windows
-- process and WSL env vars do not cross the boundary without WSLENV plumbing.

local input = app.params["in"]
local output = app.params["out"]

if not input or not output then
	print("ERROR: pass --script-param in=<path> --script-param out=<path>")
	return
end

local sprite = app.open(input)
if not sprite then
	print("ERROR: could not open " .. input)
	return
end

app.activeSprite = sprite

-- 320x64 strip -> five 64x64 frames.
app.command.ImportSpriteSheet {
	ui = false,
	type = SpriteSheetType.HORIZONTAL,
	frameBounds = Rectangle(0, 0, 64, 64),
}

print("frames after import: " .. #sprite.frames)

-- The prototype played this at 7 fps.
for _, frame in ipairs(sprite.frames) do
	frame.duration = 1.0 / 7.0
end

-- Tag names become Godot animation names via Aseprite Wizard, so this must match
-- the buddy state machine in docs/architecture.md.
local tag = sprite:newTag(1, #sprite.frames)
tag.name = "idle"
tag.aniDir = AniDir.FORWARD

sprite:saveAs(output)
print("wrote " .. output .. " with " .. #sprite.frames .. " frames and tag '" .. tag.name .. "'")
