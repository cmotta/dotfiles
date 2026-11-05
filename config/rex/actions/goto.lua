-- Go to a pane: focus it in its session and show that session in the app.
-- The inbox puts this behind each notification, so a click on "needs
-- permission" lands in the pane that asked. Any script with a block ID can
-- use it: `rex do goto session_id=ID block_id=ID` (bin/rex-goto wraps that).
local lib = require("lib")

rex.action{
  name  = "goto",
  title = "Go to pane",
  category = "Custom",
  keywords = "goto jump pane block focus show",
  args = { session_id = "string", block_id = "string" },
  run = function(ctx, args)
    local lb = assert(lib.session_call("session.list_blocks", { session_id = args.session_id }))
    local window_id
    for _, b in ipairs(lb.blocks or {}) do
      if b.block_id == args.block_id then window_id = b.window_id break end
    end
    if not window_id then error("no such block in that session: " .. args.block_id) end
    assert(lib.session_call("session.focus_block", { session_id = args.session_id, block_id = args.block_id }))
    lib.show_in_app(ctx, args.session_id, window_id)
    return { session_id = args.session_id, window_id = window_id, block_id = args.block_id }
  end,
}
