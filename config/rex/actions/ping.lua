-- Smoke test: returns the context an action receives. Useful while building.
rex.action{
  name  = "ping",
  title = "Ping (show action context)",
  category = "Custom",
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
