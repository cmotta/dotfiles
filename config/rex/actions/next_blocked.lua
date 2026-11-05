-- Jump to the next pane waiting on you, across every session: blocked first
-- (a question, a permission, a password), then error, then done. Pressing it
-- again moves on to the next one and wraps. Anything that speaks OSC 7501
-- counts, not only agents: a build or a test run that reports its state too.
local lib = require("lib")

local WAITING = { blocked = 1, error = 2, done = 3 }

local function status_of(session_id, block_id)
  local st = lib.session_call("block.method", {
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
  category = "Custom",
  keywords = "blocked waiting next jump agent question permission error done",
  run = function(ctx, args)
    local sessions = assert(rex.call("session.list", {})).sessions or {}
    local found = {}
    for _, s in ipairs(sessions) do
      local lb = lib.session_call("session.list_blocks", { session_id = s.session_id })
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
      assert(lib.session_call("session.focus_block", { session_id = target.session_id, block_id = target.block_id }))
      lib.show_in_app(ctx, target.session_id, target.window_id)
    end

    if not target then return { found = 0 } end
    return { found = #found, session = target.session, state = target.state, kind = target.kind,
             app = target.app, msg = target.msg, block_id = target.block_id, updated_at = target.at }
  end,
}
