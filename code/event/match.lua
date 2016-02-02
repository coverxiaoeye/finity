local cjson = require('cjson')
local code = require('code')
local throw = require('throw')
local const = require('const')
local play = require('thread.play')

return function(req, sess)
  local red = sess.red

  local group, err = red:hget(const.KEY_PLAYER .. '/' .. sess.id, const.KEY_GROUP)
  if not group then
    ngx.log(ngx.ERR, 'failed to do hget: ', err)
    throw(code.REDIS)
  end
  if group ~= ngx.null then
    throw(code.ILLEGAL)
  end

  -- TODO ugly matching code
  local groups, err = red:keys(const.KEY_GROUP .. '/*')
  if not groups then
    ngx.log(ngx.ERR, 'failed to do keys: ', err)
    throw(code.REDIS)
  end
  local retry, sleep, groupid, group, playerids = 0, 5, nil, nil, nil
  while retry < 2 do
    for _, v in ipairs(groups) do
      local ok, err = red:hgetall(v)
      if not ok then
        ngx.log(ngx.ERR, 'failed to do hgetall: ', err)
        throw(code.REDIS)
      end
      local g = red:array_to_hash(ok)
      if g.state == 'wait' then
        local idx = string.find(v, '/', 1, true)
        groupid = string.sub(v, idx + 1)
        group = g
      end
    end
    if groupid then break end
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
    local newgroupid, err = red:incr(const.KEY_GROUP_N)
    if not newgroupid then
      ngx.log(ngx.ERR, 'failed to do incr: ', err)
      throw(code.REDIS)
    end
    groupid = newgroupid
    group = { state = 'wait', member = cjson.encode({ [sess.id] = 1 }) }
  else
    group.state = 'begin'
    playerids = cjson.decode(group.member)
    playerids[sess.id] = 1
    group.member = cjson.encode(playerids)
  end

  local ok, err = red:watch(const.KEY_PLAYER .. '/' .. sess.id, const.KEY_GROUP .. '/' .. groupid)
  if not ok then
    ngx.log(ngx.ERR, 'failed to do watch: ', err)
    throw(code.REDIS)
  end
  local ok, err = red:multi()
  if not ok then
    ngx.log(ngx.ERR, 'failed to do watch: ', err)
    throw(code.REDIS)
  end
  local ok, err = red:hset(const.KEY_PLAYER .. '/' .. sess.id, const.KEY_GROUP, groupid)
  if not ok then
    ngx.log(ngx.ERR, 'failed to do hset: ', err)
    throw(code.REDIS)
  end
  local ok, err = red:hmset(const.KEY_GROUP .. '/' .. groupid, group)
  if not ok then
    ngx.log(ngx.ERR, 'failed to do hmset: ', err)
    throw(code.REDIS)
  end
  local ok, err = red:exec()
  if not ok then
    ngx.log(ngx.ERR, 'failed to do exec: ', err)
    throw(code.REDIS)
  end

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
    for playerid, _ in pairs(playerids) do
      sess.singlecast(playerid, resp)
    end

    ngx.timer.at(0, play, groupid)
  end
end
