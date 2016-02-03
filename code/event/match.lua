local codec = require('codec')
local code = require('code')
local throw = require('throw')
local const = require('const')
local play = require('thread.play')

return function(req, sess)
  local kv = sess.kv

  local playerkey = const.player(sess.id)
  local group = kv.call('hget', playerkey, 'group')
  if group ~= ngx.null then
    throw(code.ILLEGAL)
  end

  -- TODO ugly matching code
  local groups = kv.call('keys', const.KEY_GROUP .. '/*')
  local retry, sleep, groupid, group, ids = 0, 5, nil, nil, nil
  while retry < 2 do
    for _, v in ipairs(groups) do
      local ret = kv.call('hgetall', v)
      local g = kv.rawcall('array_to_hash', ret)
      if g.state == 'wait' then
        local idx = string.find(v, '/', 1, true)
        groupid = string.sub(v, idx + 1)
        group = g
      end
    end
    if groupid then
      break
    end
    retry = retry + 1
    if retry < 2 then
      ngx.sleep(sleep)
      local resp =
      {
        id = 0,
        event = 'retry',
        args = { n = retry, sleep = sleep }
      }
      sess.singlecast(sess.id, resp)
    end
  end
  if not groupid then
    groupid = kv.call('incr', const.groupn())
    group = { state = 'wait', member = codec.enc({ sess.id }) }
  else
    ids = codec.dec(group.member)
    ids[#ids + 1] = sess.id
    group = { state = 'begin', member = codec.enc(ids) }
  end

  local groupkey = const.group(groupid)
  kv.call('watch', playerkey, groupkey)
  kv.call('multi')
  kv.call('hset', playerkey, 'group', groupid)
  kv.call('hmset', groupkey, group)
  kv.call('exec')

  local resp =
  {
    id = req.id,
    event = 'match',
    args = { state = group.state }
  }
  sess.singlecast(sess.id, resp)

  if group.state == 'begin' then
    local resp =
    {
      id = 0,
      event = 'match',
      args = { state = group.state }
    }
    for _, v in pairs(ids) do
      sess.singlecast(v, resp)
    end

    ngx.timer.at(0, play, groupid)
  end
end
