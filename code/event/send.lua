local cjson = require('cjson')
local code = require('code')
local throw = require('throw')
local const = require('const')

return function(req, sess)
  local heroid = req.args.heroid
  local red = sess.red

  local groupid, err = red:hget(const.KEY_PLAYER .. '/' .. sess.id, const.KEY_GROUP)
  if not groupid then
    ngx.log(ngx.ERR, 'failed to do hget: ', err)
    throw(code.REDIS)
  end
  if groupid == ngx.null then
    throw(code.ILLEGAL)
  end

  local ok, err = red:hgetall(const.KEY_GROUP .. '/' .. groupid)
  if not ok then
    ngx.log(ngx.ERR, 'failed to do hgetall: ', err)
    throw(code.REDIS)
  end
  local group = red:array_to_hash(ok)
  if group.state ~= 'begin' then
    throw(code.ILLEGAL)
  end
  local playerids = cjson.decode(group.member)

  local ok, err = red:rpush(const.KEY_HERO .. '/' .. groupid, heroid)
  if not ok then
    ngx.log(ngx.ERR, 'failed to do rpush: ', err)
    throw(code.REDIS)
  end
  local resp =
  {
    id = req.id,
    event = req.event,
    args = req.args
  }
  sess.singlecast(sess.id, resp)
  local resp =
  {
    id = 0,
    event = req.event,
    args = { playerid = sess.id, heroid = heroid }
  }
  for playerid, _ in pairs(playerids) do
    sess.singlecast(playerid, resp)
  end
end