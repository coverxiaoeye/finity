local M = { channel = 'group', key = 'send' }

M.fire = function(args, sess, data)
  local heroid = args.heroid
  return
  {
    playerid = sess.id,
    heroid = heroid
  }
end

return M
