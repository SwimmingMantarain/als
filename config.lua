local win = als.create_window(SCREEN_WIDTH, 50, true) -- width, height, onAllMonitors
win:to_edge(UP)

local label = win:new_label("label", 24, 4, CENTER) -- text, font size, padding, alignment
