-- Key bindings and modes. The app ships its own defaults for splits, tabs,
-- focus, move, float, zoom and balance, so only add what it does not do.
-- After `rex config reload`, the app warns when a key here shadows a default:
-- that warning means the binding must move.

-- Resize mode: one chord to enter, then arrows or hjkl move the divider
-- 5% per press (the app default) until Escape or Enter leaves the mode.
rex.mode("resize", { exclusive = true })
rex.bind("cmd+ctrl+r", "client.mode.enter", { name = "resize" })

for key, direction in pairs{
  left = "left", right = "right", up = "up", down = "down",
  h = "left",    l = "right",     k = "up",  j = "down",
} do
  rex.bind("resize/" .. key, "pane.resize", { direction = direction })
end

rex.bind("resize/=",      "pane.balance")
rex.bind("resize/escape", "client.mode.exit")
rex.bind("resize/enter",  "client.mode.exit")
