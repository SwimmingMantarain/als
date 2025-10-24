local win = als.create_window(SCREEN_WIDTH, 50, 0xcc000000, true) -- width, height, bg color, onAllMonitors
win:to_edge(UP)

local label = win:new_label("label", 36, 4, CENTER) -- text, width, height, font size, padding, alignment
