local win = als.create_window(SCREEN_WIDTH, 50, 0xcc000000, true) -- width, height, bg color, onAllMonitors
win:to_edge(UP)

local l = win:new_label("label", 36, 4, CENTER) -- text, font size, padding, alignment

local function labelHover(label, x, y)
	label:set_bg(0xFFFF0000) -- argb red
end

l:set_callback("mousemotion", labelHover)
