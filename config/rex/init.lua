-- Rex configuration.
-- Lives in dotfiles/config/rex and is symlinked from ~/.config/rex by install.sh.
-- Rule: add only what the app does not already do. One feature per commit,
-- tested with `rex config check` then `rex config reload`.
--
--   actions/   one action per file; each shows up in the palette and `rex actions`
--   keys.lua   key bindings and modes
--   layouts.lua named pane layouts used by the open action
--   lib.lua    helpers shared by the actions
--   scripts/   `rex do` scripts that run outside the server (file and process access)
--   launchd/   agent that keeps the inbox script running on macOS
--   systemd/   user units for a Linux server

-- Every file in actions/ registers itself; drop a file in, reload, done.
local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or (os.getenv("HOME") .. "/.config/rex")
local listing = rex.exec({ "ls", "actions" }, { cwd = here })
for file in (listing.stdout or ""):gmatch("([%w_%-]+)%.lua") do
  require("actions." .. file)
end

require("keys")
