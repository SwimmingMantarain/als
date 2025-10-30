local win = als.create_window(SCREEN_WIDTH, 50, 0xcc000000, true) -- width, height, bg color, onAllMonitors
win:to_edge(UP)

local l = win:new_label("label", 36, 4, LEFT) -- text, font size, padding, alignment

local function labelOnEnter(label, x, y)
	label:set_bg(0xFFFF0000) -- argb red
	label:set_fg(0xFF00FF00) -- argb green
	label:set_text("beans")
end

local function labelOnLeave(label, x, y)
	label:set_bg(0xFF00FF00) -- argb green
	label:set_fg(0xFFFF0000) -- argb red
	label:set_text("ballin'")
end

l:set_callback("mouseenter", labelOnEnter)
l:set_callback("mouseleave", labelOnLeave)
