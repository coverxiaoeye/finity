local M = { channel = 'self', key = 'ping' }

M.fire = function(args, sess, data, red)
  return args
end

return M