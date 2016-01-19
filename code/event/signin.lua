local quote = ngx.quote_sql_str
local throw = require('throw')

local M = { channel = 'self', key = 'signin' }

M.fire = function(args, sess, data, red)
  local sid = args.sid

  -- TODO sid verification by 3rd-party platform, user system, gate server, etc.
  -- just get id from mysql
  local sql = 'SELECT id, nick, lv, exp FROM player WHERE sid = %s'
  local player = data.queryone(sql, quote(sid))

  if not player then
    throw(1001)
  end

  sess.id = player.id
  player.id = nil

  return player
end

return M
