--!nonstrict
local form = require("./lib/auth-form.luau").new("reprompt")

function onOpen(_context)
  form.open()
end

function onFrameTick(deltaMs)
  form.tick(deltaMs)
end
