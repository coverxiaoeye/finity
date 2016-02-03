local codec = require('codec')
local code = require('code')
local throw = require('throw')
local const = require('const')

return function(req, sess)
  local heroid = req.args.heroid
  local kv = sess.kv

  local groupid = kv.call('hget', const.player(sess.id), 'group')
  if groupid == ngx.null then
    throw(code.ILLEGAL)
  end

  local ret = kv.call('hgetall', const.group(groupid))
  local group = kv.rawcall('array_to_hash', ret)
  if group.state ~= 'begin' then
    throw(code.ILLEGAL)
  end
  local ids = codec.dec(group.member)
  kv.call('rpush', const.hero(groupid), heroid)

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
  for _, v in pairs(ids) do
    sess.singlecast(v, resp)
  end
end