-- inbox.lua: notify me when a pane needs me.
--
--   rex do ~/.config/rex/scripts/inbox.lua --all
--
-- Listens to program status reports (OSC 7501) from every session, so
-- anything that speaks the protocol feeds it: rx run, Claude Code, more to
-- come. A pane going blocked or error notifies at once. Done notifies only
-- when the work took at least done_after seconds (default 10), so a quick
-- `rx run ls` stays quiet and a long build does not. Repeated reports of the
-- same state are ignored; a program must leave a state before it can ring
-- for it again.
--
-- Delivery goes through `notify` (bin/notify): the desktop on macOS, ntfy
-- where ~/.notify.local names a topic. On macOS a click on the banner goes
-- to the pane (notify -x, bin/rex-goto, the goto action). It runs all the time as a launchd
-- agent on macOS (config/rex/launchd) and a systemd user unit on Linux
-- (config/rex/systemd); both restart it when the server goes away. On macOS
-- install.sh also starts one agent per host in `rex hosts`, with host=LABEL,
-- so panes on those servers ring this desktop too.
--
-- Args: done_after=SECONDS   notify=COMMAND (default "notify")
--       host=LABEL   when run against another server (rex -S LABEL do ...):
--                    titles start with LABEL and only this desktop rings,
--                    since that host's own inbox already pushes to the phone.

local done_after = tonumber(rex.args.done_after) or 10
local notify_cmd = rex.args.notify or "notify"
local host = rex.args.host

-- Last state seen per record, keyed by block and record ID.
local seen = {}

local session_labels = {}
local function session_label(session_id)
  if not session_labels[session_id] then
    local list = rex.call("session.list", {}) or {}
    for _, s in ipairs(list.sessions or list) do
      session_labels[s.session_id or s.id] = s.label
    end
  end
  return session_labels[session_id] or "rex"
end

local function block_label(session_id, block_id)
  local r = rex.call("session.list_blocks", { session_id = session_id }) or {}
  for _, b in ipairs(r.blocks or {}) do
    if b.block_id == block_id and b.label and b.label ~= "" then
      return b.label
    end
  end
  return nil
end

local function describe(record, elapsed)
  local app = record.effective_app or record.app or "program"
  local detail = record.msg or record.title
  if record.state == "blocked" then
    local waits = {
      permission = "needs permission",
      question = "has a question",
      auth = "needs a credential",
    }
    local what = waits[record.kind or ""] or "is waiting for you"
    return app .. " " .. what .. (detail and (": " .. detail) or ""), "high", "raised_hand"
  elseif record.state == "error" then
    return app .. " failed" .. (detail and (": " .. detail) or ""), "high", "x"
  else
    local took = elapsed and string.format(" after %ds", elapsed) or ""
    return app .. " finished" .. took .. (detail and (": " .. detail) or ""), "default", "white_check_mark"
  end
end

local function notify(ctx, record, elapsed)
  local title = session_label(ctx.session_id)
  local pane = block_label(ctx.session_id, ctx.block_id)
  if pane then title = title .. " / " .. pane end
  if host then title = host .. ": " .. title end
  local body, priority, tag = describe(record, elapsed)
  local argv = { notify_cmd, "-p", priority, "-t", tag }
  if host then argv[#argv + 1] = "-l" end
  -- A click on the banner lands in the pane (bin/rex-goto, macOS only).
  local goto_cmd = "rex-goto " .. (host and ("-S " .. host .. " ") or "")
    .. ctx.session_id .. " " .. ctx.block_id
  argv[#argv + 1] = "-x"
  argv[#argv + 1] = goto_cmd
  argv[#argv + 1] = title
  argv[#argv + 1] = body
  local r = rex.exec(argv)
  if not r or not r.ok then
    io.stderr:write("inbox: notify failed: " .. ((r and r.stderr) or "no result") .. "\n")
  end
end

rex.on("terminal.program_status_changed", function(ctx, ev)
  local record = ev.record
  local key = ctx.block_id .. "/" .. (ev.id or "")
  local prev = seen[key]
  local now = os.time()
  if prev and prev.state == record.state then return end

  local started = (record.state == "working") and now or (prev and prev.started)
  seen[key] = { state = record.state, started = started }

  if record.state == "blocked" or record.state == "error" then
    notify(ctx, record, nil)
  elseif record.state == "done" and prev and prev.state == "working" then
    local elapsed = now - (prev.started or now)
    if elapsed >= done_after then notify(ctx, record, elapsed) end
  end
end)

rex.on("terminal.program_status_removed", function(ctx, ev)
  for _, id in ipairs(ev.ids or {}) do
    seen[ctx.block_id .. "/" .. id] = nil
  end
end)

rex.on("block_closed", function(ctx, ev)
  local prefix = (ev.block_id or "") .. "/"
  for key in pairs(seen) do
    if key:sub(1, #prefix) == prefix then seen[key] = nil end
  end
end)

rex.on("session_destroyed", function(ctx, ev)
  -- A server event: the session is in ev, not ctx.
  local id = ev.session_id or ctx.session_id
  if id then session_labels[id] = nil end
end)
