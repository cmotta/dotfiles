-- Open a tab in a session, from wherever you are. The session is a topic
-- (work, personal, dotfiles), the tab is a task, the path is where its shells
-- start. Creates the session when the label is new. From a shell: `rx tab`
-- and `rx ws`, see zsh/functions/rx. Layouts are named in layouts.lua.
local lib = require("lib")
local layouts = require("layouts")

rex.action{
  name  = "open",
  title = "Open tab in session",
  category = "Custom",
  keywords = "tab window session topic layout open new",
  args = { session = "string?", path = "string", layout = "string?" },
  run = function(ctx, args)
    local path = args.path
    -- Relative paths would resolve against the server, not the caller's shell.
    if path:sub(1, 1) ~= "/" then
      error("path must be absolute (use $PWD or the rx shell function): " .. path)
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
      local w = assert(lib.session_call("session.new_window", { session_id = session_id, layout = layout }))
      window_id = w.window_id
    else
      local r = assert(rex.call("session.create", {
        label = args.session,
        initial_windows = {{ layout = layout }},
      }))
      session_id, created = r.session_id, true
      window_id = r.initial_windows[1].window_id
    end

    lib.show_in_app(ctx, session_id, window_id)
    return { session_id = session_id, window_id = window_id, created = created,
             layout = args.layout or "shell" }
  end,
}
