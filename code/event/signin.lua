local quote = ngx.quote_sql_str
local code = require('code')
local throw = require('throw')
local const = require('const')

local M = { channel = 'self', key = 'signin' }

M.fire = function(args, sess, data, red)
  if sess.id > 0 then
    throw(code.SIGNIN_ALREADY)
  end

  local sid = args.sid

  -- TODO sid verification by 3rd-party platform, user system, gate server, etc.
  -- just get id from mysql
  local sql = 'SELECT id, nick, lv, exp FROM player WHERE sid = %s'
  local player = data.queryone(sql, quote(sid))

  if not player then
    throw(code.SIGNIN_UNAUTH)
  end

  local ok, err = red:sismember(const.KEY_SESSION, player.id)
  if not ok then
    ngx.log(ngx.ERR, 'failed to do sismember: ', err)
    throw(code.REDIS)
  end
  if ok == '1' then
    throw(code.SIGNIN_ALREADY)
  end

  local ok, err = red:sadd(const.KEY_SESSION, player.id)
  if not ok then
    ngx.log(ngx.ERR, 'failed to do sadd: ', err)
    throw(code.REDIS)
  end

  sess.id = player.id
  player.id = nil

  return player
end

return M
