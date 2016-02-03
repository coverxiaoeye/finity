local codec = require('codec')
local code = require('code')
local throw = require('throw')
local const = require('const')

--出兵事件处理
return function(req, sess)
  local heroid = req.args.heroid
  local kv = sess.kv

  --判断用户是否在游戏组中
  local groupid = kv.call('hget', const.player(sess.id), 'group')
  if groupid == ngx.null then
    throw(code.ILLEGAL)
  end

  --判定游戏是否为begin状态, 并获取游戏组中的所有玩家
  local ret = kv.call('hgetall', const.group(groupid))
  local group = kv.rawcall('array_to_hash', ret)
  if group.state ~= 'begin' then
    throw(code.ILLEGAL)
  end
  --将英雄放入
  kv.call('rpush', const.hero(groupid), heroid)

  --单播出兵返回
  local resp = { id = req.id, event = req.event, args = req.args }
  sess.singlecast(sess.id, resp)

  --组播出兵事件(效率,未采用groupcast)
  local ids = codec.dec(group.member)
  local resp = { id = 0, event = req.event, args = { playerid = sess.id, heroid = heroid } }
  for _, v in pairs(ids) do
    sess.singlecast(v, resp)
  end
end