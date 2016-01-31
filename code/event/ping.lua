local M = { channel = 'self', key = 'ping' }

M.fire = function(args, sess, data)
  return args
end

return M