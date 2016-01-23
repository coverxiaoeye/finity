local M = { channel = 'all', key = 'chat' }

M.fire = function(args, sess, data, red)
  return
  {
    playerid = sess.id,
    message = args
  }
end

return M