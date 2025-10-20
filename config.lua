window1 = als.create_window(200, 200, 0, 0)

function Callback()
    print("cool!")
end

window1:set_callback("click", Callback)

print("Created Window: ", window1)
