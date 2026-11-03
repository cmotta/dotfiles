-- Rex configuration.
-- Lives in dotfiles/config/rex and is symlinked from ~/.config/rex by install.sh.
-- Rule: add only what the app does not already do. One feature per commit,
-- tested with `rex config check` then `rex config reload`.

require("actions")
require("keys")
