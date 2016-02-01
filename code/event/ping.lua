local M = { channel = 'self', key = 'ping', tx = false }

M.fire = function(args, sess, data)
  return args
end

return M