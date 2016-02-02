local M = { channel = 'self', key = 'ping', tx = false }

M.fire = function(args)
  return args
end

return M