--!nonstrict
local form = require("./lib/auth-form.luau").new("unlock")

function onOpen(_context)
  form.open()
end

function onFrameTick(deltaMs)
  form.tick(deltaMs)
end
