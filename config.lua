Window1 = als.create_window(200, 200, true) -- width, height, onAllMonitors
Window1:to_edge(UP)
Window1:draw_text(0, 100, "lua!", "arial", 64)

local function keyboard(window, key)
    if key == 97 then
        window:to_edge(LEFT)
    elseif key == 119 then
        window:to_edge(UP)
    elseif key == 115 then
        window:to_edge(DOWN)
    elseif key == 100 then
        window:to_edge(RIGHT)
    else
        window:to_edge(CENTER)
    end
end

Window1:set_callback("key", keyboard)
