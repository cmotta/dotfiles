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

-- Call a session-scoped method; attach first only when the connection is not
-- attached. Never detach: from a key the connection is the app's own, and
-- detaching it from a session it shows breaks the app.
local function session_call(method, args)
  local r, err = rex.call(method, args)
  if r == nil and err and err:find("not attached") then
    rex.call("session.attach", { session_id = args.session_id })
    r, err = rex.call(method, args)
  end
  return r, err
end

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
      local w = assert(session_call("session.new_window", { session_id = session_id, layout = layout }))
      window_id = w.window_id
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

-- Jump to the next pane waiting on you, across every session: blocked first
-- (a question, a permission, a password), then error, then done. Pressing it
-- again moves on to the next one and wraps. Anything that speaks OSC 7501
-- counts, not only agents: a build or a test run that reports its state too.
local WAITING = { blocked = 1, error = 2, done = 3 }

local function status_of(session_id, block_id)
  local st = session_call("block.method", {
    session_id = session_id, block_id = block_id, method = "program_status",
  })
  local best
  for _, r in ipairs(st and st.records or {}) do
    local rank = WAITING[r.state]
    if rank and (not best or rank < best.rank) then
      best = { rank = rank, state = r.state, kind = r.kind, at = r.updated_at or "",
               app = r.effective_app or r.app, msg = r.msg or r.title }
    end
  end
  return best
end

rex.action{
  name  = "next_blocked",
  title = "Next pane waiting on you",
  category = "WTF",
  keywords = "blocked waiting next jump agent question permission error done",
  run = function(ctx, args)
    local sessions = assert(rex.call("session.list", {})).sessions or {}
    local found = {}
    for _, s in ipairs(sessions) do
      local lb = session_call("session.list_blocks", { session_id = s.session_id })
      for _, b in ipairs(lb and lb.blocks or {}) do
        if b.placement == "placed" and b.flavor == "com.superlogical.terminal.shell" then
          local w = status_of(s.session_id, b.block_id)
          if w then
            w.session_id, w.session, w.block_id, w.window_id = s.session_id, s.label, b.block_id, b.window_id
            found[#found + 1] = w
          end
        end
      end
    end

    -- Most urgent state first; within a state, the most recent change first,
    -- so the pane that just asked for you comes before one done an hour ago.
    table.sort(found, function(a, b)
      if a.rank ~= b.rank then return a.rank < b.rank end
      return a.at > b.at
    end)

    -- Continue after the current pane when it is one of them, else start at the top.
    local target = found[1]
    for i, w in ipairs(found) do
      if w.block_id == ctx.block_id then target = found[i % #found + 1] break end
    end

    if target then
      assert(session_call("session.focus_block", { session_id = target.session_id, block_id = target.block_id }))
      if ctx.origin == "key" or ctx.origin == "palette" then
        rex.client.queue("session.select", { session_id = target.session_id, window_id = target.window_id })
      end
    end

    if not target then return { found = 0 } end
    return { found = #found, session = target.session, state = target.state, kind = target.kind,
             app = target.app, msg = target.msg, block_id = target.block_id, updated_at = target.at }
  end,
}
