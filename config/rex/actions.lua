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

-- One session per repo, labeled after the folder. Jumps to the session if it
-- exists, otherwise creates it with one shell in the repo. From a shell:
--   rex do repo path=$PWD        (or `rp [dir]`, see zsh/functions/rp)
local function basename(path)
  return (path:gsub("/+$", "")):match("([^/]+)$")
end

rex.action{
  name  = "repo",
  title = "Open repo session",
  category = "WTF",
  keywords = "repo session project workspace open",
  args = { path = "string" },
  run = function(ctx, args)
    local path = args.path
    -- Relative paths would resolve against the server, not the caller's shell.
    if path:sub(1, 1) ~= "/" then
      error("path must be absolute (use $PWD or the rp shell function): " .. path)
    end
    local probe = rex.exec({ "test", "-d", path })
    if not (probe and probe.ok) then error("not a directory: " .. path) end
    local label = basename(path)
    if not label then error("path must name a folder: " .. path) end

    local list = assert(rex.call("session.list", {}))
    local session_id
    for _, s in ipairs(list.sessions or {}) do
      if s.label == label then session_id = s.session_id break end
    end

    local created = false
    if not session_id then
      local r = assert(rex.call("session.create", {
        label = label,
        initial_windows = {{
          layout = { block = {
            flavor  = "com.superlogical.terminal.shell",
            options = { cwd = path },
          } },
        }},
      }))
      session_id, created = r.session_id, true
    end

    -- Jump to it when invoked from the app. From the CLI the app only obeys
    -- with Remote Control on (Settings > Rex Server), so skip it there.
    if ctx.origin == "key" or ctx.origin == "palette" then
      rex.client.queue("session.select", { session_id = session_id })
    end

    return { session_id = session_id, label = label, created = created }
  end,
}
