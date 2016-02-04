local codec = require('codec')
local code = require('code')
local throw = require('throw')
local const = require('const')
local play = require('thread.play')

--快速匹配事件处理
return function(req, sess)
  local kv = sess.kv

  --确认玩家未在游戏组中
  local playerkey = const.player(sess.id)
  local group = kv.call('hget', playerkey, 'group')
  if group ~= ngx.null then
    throw(code.ILLEGAL)
  end

  --遍历所有状态为wait的游戏组, 未找到则等5秒后重试
  local groups = kv.call('keys', const.KEY_GROUP .. '/*')
  local groupid, group, ids

  for _, v in ipairs(groups) do
    local ret = kv.call('hgetall', v)
    local g = kv.rawcall('array_to_hash', ret)
    if g.state == 'wait' then
      local idx = string.find(v, '/', 1, true)
      groupid = string.sub(v, idx + 1)
      group = g
    end
  end

  if not groupid then
    --未找到匹配的游戏则创建一个新的并加入,状态为wait
    groupid = kv.call('incr', const.groupn())
    group = { state = 'wait', member = codec.enc({ sess.id }) }
  else
    --找到后加入
    ids = codec.dec(group.member)
    ids[#ids + 1] = sess.id
    group = { state = 'begin', member = codec.enc(ids) }
  end

  --更新游戏,处理并发
  local groupkey = const.group(groupid)
  kv.call('watch', playerkey, groupkey)
  kv.call('multi')
  kv.call('hset', playerkey, 'group', groupid)
  kv.call('hmset', groupkey, group)
  kv.call('exec')

  --单播处理结果
  local resp = { id = req.id, event = 'match', args = { state = group.state } }
  sess.singlecast(sess.id, resp)

  --如果游戏状态为开始则启动游戏线程
  if group.state == 'begin' then
    --组播游戏开始事件(效率,未用groupcast)
    local resp = { id = 0, event = 'match', args = { state = group.state } }
    for _, v in pairs(ids) do
      sess.singlecast(v, resp)
    end
    --启动游戏线程
    ngx.timer.at(0, play, groupid)
  end
end
