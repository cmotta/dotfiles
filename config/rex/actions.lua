-- Custom actions. Each shows up in the command palette and in `rex actions`,
-- and runs from the shell with `rex do NAME k=v`.

-- Smoke test: returns the context an action receives. Useful while building.
rex.action{
  name  = "ping",
  title = "Ping (show action context)",
  category = "WTF",
  run = function(ctx, args)
    return {
      session_id = ctx.session_id,
      block_id   = ctx.block_id,
      client_id  = ctx.client_id,
      origin     = ctx.origin,
      args       = args,
    }
  end,
}

-- Open a tab in a session, from wherever you are. The session is a topic
-- (ed, twk, dotfiles), the tab is a task, the path is where its shells start.
-- Creates the session when the label is new. From a shell: `rt`, see
-- zsh/functions/rt. Layouts are named in layouts.lua.
local layouts = require("layouts")

rex.action{
  name  = "open",
  title = "Open tab in session",
  category = "WTF",
  keywords = "tab window session topic layout open new",
  args = { session = "string?", path = "string", layout = "string?" },
  run = function(ctx, args)
    local path = args.path
    -- Relative paths would resolve against the server, not the caller's shell.
    if path:sub(1, 1) ~= "/" then
      error("path must be absolute (use $PWD or the rt shell function): " .. path)
    end
    local probe = rex.exec({ "test", "-d", path })
    if not (probe and probe.ok) then error("not a directory: " .. path) end

    local build = layouts[args.layout or "shell"]
    if not build then error("unknown layout: " .. tostring(args.layout)) end
    local layout = build(path)

    local session_id, created = ctx.session_id, false
    if args.session then
      session_id = nil
      local list = assert(rex.call("session.list", {}))
      for _, s in ipairs(list.sessions or {}) do
        if s.label == args.session then session_id = s.session_id break end
      end
    end
    if not session_id and not args.session then
      error("no current session; pass session=LABEL")
    end

    local window_id
    if session_id then
      -- A window can only be added to a session this connection is attached to.
      if session_id ~= ctx.session_id then
        assert(rex.call("session.attach", { session_id = session_id }))
      end
      local w = assert(rex.call("session.new_window", { session_id = session_id, layout = layout }))
      window_id = w.window_id
      if session_id ~= ctx.session_id then
        rex.call("session.detach", { session_id = session_id })
      end
    else
      local r = assert(rex.call("session.create", {
        label = args.session,
        initial_windows = {{ layout = layout }},
      }))
      session_id, created = r.session_id, true
      window_id = r.initial_windows[1].window_id
    end

    -- Jump there when invoked from the app. From the CLI the app only obeys
    -- with Remote Control on (Settings > Rex Server), so skip it there.
    if ctx.origin == "key" or ctx.origin == "palette" then
      rex.client.queue("session.select", { session_id = session_id, window_id = window_id })
    end

    return { session_id = session_id, window_id = window_id, created = created,
             layout = args.layout or "shell" }
  end,
}
