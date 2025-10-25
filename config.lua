local win = als.create_window(SCREEN_WIDTH, 50, 0xcc000000, true) -- width, height, bg color, onAllMonitors
win:to_edge(UP)

local l = win:new_label("label", 36, 4, CENTER) -- text, font size, padding, alignment

local function labelHover(label)
	label:set_bg(0xFFFF0000)
end

l:set_callback("mouseenter", labelHover)
