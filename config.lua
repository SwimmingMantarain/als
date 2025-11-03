local win = als.create_window(SCREEN_WIDTH, 50, "all") -- width, height, Name of monitor (e.g. DP-1, or All monitors)
win:to_edge(UP)

local label = win:new_label("text", 36)
label:to_edge(LEFT)
