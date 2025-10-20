Window1 = als.create_window(200, 200, 0, 0)

function Leftpress(window)
    window:set_color(0xFFFF0000) -- ARGB
end

function Leftrelease(window)
    window:set_color(0xFF00FF00)
end

function Motion(window)
    window:set_color(0xFFFFFF00)
end

function Enter(window)
    window:set_color(0xFF00FFFF)
end

function Leave(window)
    window:set_color(0xFF0000FF)
end

Window1:set_callback("leftpress", Leftpress)
Window1:set_callback("leftrelease", Leftrelease)
Window1:set_callback("mousemotion", Motion)
Window1:set_callback("mouseenter", Enter)
Window1:set_callback("mouseleave", Leave)

print("Created Window: ", Window1)
