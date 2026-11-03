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
