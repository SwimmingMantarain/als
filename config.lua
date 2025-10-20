window1 = als.create_window(200, 200, 0, 0)

function Callback(window)
    window:set_color(0xFFFF0000) -- ARGB
end

window1:set_callback("click", Callback)

print("Created Window: ", window1)
