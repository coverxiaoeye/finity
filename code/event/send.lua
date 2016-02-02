local M = { channel = 'group', key = 'send', tx = false }

M.fire = function(args, sess)
  local heroid = args.heroid
  return
  {
    playerid = sess.id,
    heroid = heroid
  }
end

return M
