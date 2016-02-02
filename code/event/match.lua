local code = require('code')
local throw = require('throw')
local const = require('const')
local play = require('thread.play')

return function(req, sess)
  local red = sess.red
  -- TODO ugly matching code
  local groups, err = red:keys(const.KEY_GROUP .. '/*')
  if not groups then
    ngx.log(ngx.ERR, 'failed to do keys: ', err)
    throw(code.REDIS)
  end
  local retry, sleep, group, found = 0, 5, 0, false
  while retry < 2 do
    local resp =
    {
      id = 0,
      event = 'retry',
      args = { n = retry, sleep = sleep }
    }
    sess.singlecast(sess.id, resp)
    retry = retry + 1

    for _, v in ipairs(groups) do
      local n, err = red:scard(v)
      if not n then
        ngx.log(ngx.ERR, 'failed to do scard: ', err)
        throw(code.REDIS)
      end
      if n == 1 then
        local ok, err = red:watch(v)
        if not ok then
          ngx.log(ngx.ERR, 'failed to do watch: ', err)
          throw(code.REDIS)
        end
        local ok, err = red:multi()
        if not ok then
          ngx.log(ngx.ERR, 'failed to do multi: ', err)
          throw(code.REDIS)
        end
        local ok, err = red:sadd(v, sess.id)
        if not ok then
          ngx.log(ngx.ERR, 'failed to do sadd: ', err)
          throw(code.REDIS)
        end
        local ok = red:exec()
        if ok then
          local idx = string.find(v, '/', 1, true)
          group = tonumber(string.sub(v, idx + 1))
        end
      end
    end
    if group > 0 then
      found = true
      break
    end
    if retry < 2 then
      ngx.sleep(sleep)
    end
  end
  if not found then
    local newgroup, err = red:incr(const.KEY_GROUP_N)
    if not newgroup then
      ngx.log(ngx.ERR, 'failed to do incr: ', err)
      throw(code.REDIS)
    end
    local ok, err = red:sadd(const.KEY_GROUP .. '/' .. newgroup, sess.id)
    if not ok then
      ngx.log(ngx.ERR, 'failed to do sadd: ', err)
      throw(code.REDIS)
    end
    group = newgroup
  end
  sess.group = group

  if found then
    sess.t_play = ngx.thread.spawn(play, sess)
  end

  local resp =
  {
    id = req.id,
    event = 'match',
    args = { create = not found }
  }
  sess.singlecast(sess.id, resp)
end
