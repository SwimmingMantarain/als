local win = als.create_window(SCREEN_WIDTH, 50, true) -- width, height, onAllMonitors
win:to_edge(UP)

local label = win:new_label("label", 100, 40, 36, 8, CENTER) -- text, width, height, font size, padding, alignment
