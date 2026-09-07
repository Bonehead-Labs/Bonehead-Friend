-- Replace individual frames of an .aseprite from PNGs, in place.
--
--   Aseprite.exe -b --script-param src=<file.aseprite> \
--                   --script-param patch=<frame>=<png>[,<frame>=<png>...] \
--                   --script _patch_frames.lua
--
-- Frame numbers are 1-based and global across the whole file, the way `--list-tags`
-- reports them, not per-tag. `art/tools/clean_buddy_frames.py` prints the right numbers.
--
-- Why a patch rather than a rebuild: `_build_body.lua` reconstructs the entire body file
-- from a folder of frames and re-authors every tag, which is the right tool when the frame
-- *count* changes (adding a walk cycle). Repairing three frames of seventy-four does not
-- need the tags touched, and re-authoring them is how a tag range silently shifts.

local src = app.params["src"]
local patch = app.params["patch"]
if not src or not patch then
    print("ERROR: need --script-param src= and --script-param patch=")
    return
end

local sprite = app.open(src)
if not sprite then
    print("ERROR: could not open " .. src)
    return
end

local layer = sprite.layers[1]
local applied = 0

for pair in string.gmatch(patch, "[^,]+") do
    local num, png = string.match(pair, "^(%d+)=(.+)$")
    if not num then
        print("ERROR: bad patch entry " .. pair)
        return
    end
    num = tonumber(num)
    if num < 1 or num > #sprite.frames then
        print("ERROR: frame " .. num .. " out of range 1.." .. #sprite.frames)
        return
    end

    local incoming = app.open(png)
    if not incoming then
        print("ERROR: could not open " .. png)
        return
    end
    if incoming.width ~= sprite.width or incoming.height ~= sprite.height then
        print(string.format("ERROR: %s is %dx%d, expected %dx%d",
            png, incoming.width, incoming.height, sprite.width, sprite.height))
        return
    end

    -- Flatten whatever the PNG opened as into a single image, then drop it on the frame.
    local flat = Image(incoming.width, incoming.height, incoming.colorMode)
    flat:drawSprite(incoming, 1, Point(0, 0))
    sprite:newCel(layer, num, flat, Point(0, 0))
    incoming:close()

    applied = applied + 1
    print(string.format("patched frame %d from %s", num, png))
end

sprite:saveAs(src)
sprite:close()
print(string.format("PATCHED %d frame(s) into %s", applied, src))
