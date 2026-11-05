-- Helpers shared by the actions.
local M = {}

-- Call a session-scoped method; attach first only when the connection is not
-- attached. Never detach: from a key the connection is the app's own, and
-- detaching it from a session it shows breaks the app.
function M.session_call(method, args)
  local r, err = rex.call(method, args)
  if r == nil and err and err:find("not attached") then
    rex.call("session.attach", { session_id = args.session_id })
    r, err = rex.call(method, args)
  end
  return r, err
end

-- Show a window in the app when the action came from the app. From the CLI
-- the app only obeys with Remote Control on (Settings > Rex Server), so skip.
function M.show_in_app(ctx, session_id, window_id)
  if ctx.origin == "key" or ctx.origin == "palette" then
    rex.client.queue("session.select", { session_id = session_id, window_id = window_id })
  end
end

return M
