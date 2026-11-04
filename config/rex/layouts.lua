-- Named window layouts for the `open` action. Each is a function of the
-- directory and returns a layout node as session.new_window expects it:
-- { block = { flavor, options, label } } or
-- { split = { direction = "horizontal"|"vertical", ratio, before, after } }.

local function shell(path, label)
  return { block = {
    flavor  = "com.superlogical.terminal.shell",
    options = { cwd = path },
    label   = label,
  } }
end

local function split(direction, ratio, before, after)
  return { split = { direction = direction, ratio = ratio, before = before, after = after } }
end

return {
  -- One shell. The default.
  shell = function(path) return shell(path) end,

  -- Port of bin/dev-workspace (tmux):
  --   main terminal (large) | side pane, full height
  --   dev server | logs     |
  dev = function(path)
    return split("horizontal", 0.6,
      split("vertical", 0.7,
        shell(path, "main"),
        split("horizontal", 0.5, shell(path, "server"), shell(path, "logs"))),
      shell(path, "side"))
  end,
}
