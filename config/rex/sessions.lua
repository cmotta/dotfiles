-- Save and restore the programs running in each pane. The server already
-- keeps sessions, tabs, layouts, labels and each shell's directory across a
-- restart; only running programs die. This script records what each pane
-- runs so they can be typed back after the restart.
--
--   rex do ~/.config/rex/sessions.lua op=save          record running programs
--   rex do ~/.config/rex/sessions.lua op=restore       type them back, no Enter
--   rex do ~/.config/rex/sessions.lua op=restore run=1 type them and run them
--   rex do ~/.config/rex/sessions.lua op=show          print the record
--
-- Run it on the machine that hosts the server: it reads the process table
-- there. From a shell use `rx save` and `rx restore`. On miles a systemd timer
-- saves every two minutes and the service saves again on stop.

local args = rex.args or {}
local op = args.op or "show"
local file = args.file or (os.getenv("HOME") .. "/.local/state/rex/programs.json")
local SHELL_FLAVOR = "com.superlogical.terminal.shell"
local SHELLS = { login = true, zsh = true, bash = true, sh = true, dash = true, fish = true }

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function write_file(path, s)
  rex.exec({ "mkdir", "-p", path:match("^(.*)/[^/]*$") })
  local f = assert(io.open(path, "w"))
  f:write(s)
  f:close()
end

-- Process table as { pid = { ppid, cmd } }, read once per save.
local function processes()
  local r = rex.exec({ "ps", "-eo", "pid=,ppid=,args=" })
  local t = {}
  for line in (r.stdout or ""):gmatch("[^\n]+") do
    local pid, ppid, cmd = line:match("^%s*(%d+)%s+(%d+)%s+(.*)$")
    if pid then t[tonumber(pid)] = { ppid = tonumber(ppid), cmd = cmd } end
  end
  return t
end

local function is_shell(cmd)
  local first = cmd:match("^(%S+)") or ""
  local base = first:match("([^/]+)$") or first
  return SHELLS[(base:gsub("^%-", ""))] == true
end

-- The first descendant of the pane's top process that is not a shell. Shell
-- wrappers (login, nested zsh) are skipped; the program they run is returned.
local function foreground(procs, top)
  local queue, seen = { top }, { [top] = true }
  while #queue > 0 do
    local pid = table.remove(queue, 1)
    local p = procs[pid]
    if p and pid ~= top and not is_shell(p.cmd) then return p.cmd end
    for child, cp in pairs(procs) do
      if cp.ppid == pid and not seen[child] then
        seen[child] = true
        queue[#queue + 1] = child
      end
    end
  end
end

local function pane_state(session_id, block_id)
  local st = rex.call("block.method", { session_id = session_id, block_id = block_id, method = "pwd" })
  if not st then return nil end
  local path = (st.pwd or ""):gsub("^file://[^/]*", "")
  path = path:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
  return { cwd = path, pid = st.owner and st.owner.pid }
end

local function shell_panes()
  local out = {}
  for _, s in ipairs(assert(rex.call("session.list", {})).sessions or {}) do
    -- A script hears only the session named by -s or the environment; block
    -- calls on other sessions fail until the script attaches to them.
    rex.call("session.attach", { session_id = s.session_id })
    local lb = assert(rex.call("session.list_blocks", { session_id = s.session_id }))
    for _, b in ipairs(lb and lb.blocks or {}) do
      if b.placement == "placed" and b.flavor == SHELL_FLAVOR then
        out[#out + 1] = { session = s.label, session_id = s.session_id,
                          block_id = b.block_id, window_id = b.window_id, label = b.label }
      end
    end
  end
  return out
end

-- A claude started without a conversation flag is restored with --continue so
-- it picks up the latest conversation in that directory.
local function restore_command(cmd)
  local first = cmd:match("^(%S+)") or ""
  if (first:match("([^/]+)$") or first) == "claude"
     and not cmd:find("%-%-continue") and not cmd:find("%-%-resume")
     and not cmd:find("%s%-[cr]%f[%s%z]") then
    return cmd .. " --continue"
  end
  return cmd
end

local ops = {}

function ops.save()
  local procs = processes()
  local records = {}
  for _, pane in ipairs(shell_panes()) do
    local st = pane_state(pane.session_id, pane.block_id)
    local cmd = st and st.pid and foreground(procs, st.pid)
    if cmd then
      pane.cwd, pane.cmd, pane.at = st.cwd, cmd, os.date("!%Y-%m-%dT%H:%M:%SZ")
      records[#records + 1] = pane
    end
  end
  write_file(file, rex.json.encode(records))
  return { saved = #records, file = file }
end

function ops.show()
  local s = read_file(file)
  if not s then return { file = file, records = {} } end
  return { file = file, records = rex.json.decode(s) }
end

function ops.restore()
  local s = read_file(file)
  if not s then error("nothing saved at " .. file) end
  local procs = processes()
  local live = {}
  for _, pane in ipairs(shell_panes()) do live[pane.block_id] = pane end
  local run = args.run and args.run ~= "0" and args.run ~= "false"
  local typed, skipped = {}, {}
  for _, rec in ipairs(rex.json.decode(s)) do
    local pane = live[rec.block_id]
    local st = pane and pane_state(pane.session_id, pane.block_id)
    local reason
    if not pane then reason = "pane is gone"
    elseif st and st.pid and foreground(procs, st.pid) then reason = "already running a program"
    end
    if reason then
      skipped[#skipped + 1] = { session = rec.session, label = rec.label, cmd = rec.cmd, why = reason }
    else
      local cmd = restore_command(rec.cmd)
      if st and st.cwd ~= rec.cwd then cmd = "cd " .. rec.cwd .. " && " .. cmd end
      assert(rex.call("block.method", { session_id = pane.session_id, block_id = pane.block_id,
                                        method = "write", args = { data = cmd .. (run and "\n" or "") } }))
      typed[#typed + 1] = { session = rec.session, label = rec.label, cmd = cmd }
    end
  end
  return { ran = run, typed = typed, skipped = skipped }
end

local f = ops[op]
if not f then error("unknown op: " .. tostring(op) .. " (save, restore, show)") end
return f()
