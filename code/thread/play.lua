local cjson = require('cjson')
local redis = require('resty.redis')
local config = require('config')
local code = require('code')
local throw = require('throw')
local const = require('const')

local function singlecast(red, playerid, resp)
  local ok, err = red:publish(resp.event .. '/' .. playerid, cjson.encode(resp))
  if not ok then
    ngx.log(ngx.ERR, 'failed to do publish: ', err)
    throw(code.REDIS)
  end
end

return function(premature, groupid)
  if premature then
    return
  end
  local red, err = redis:new()
  if not red then
    ngx.log(ngx.ERR, 'failed to new redis: ', err)
    return
  end
  red:set_timeout(config.redis.timeout)
  local ok, err = red:connect(config.redis.host)
  if not ok then
    ngx.log(ngx.ERR, 'failed to connect to redis: ', err)
    return
  end

  -- 3 minutes game, 5 second to sync data
  local key = const.KEY_GROUP .. '/' .. groupid
  while true do
    local ok, err = red:hgetall(key)
    if not ok then
      ngx.log(ngx.ERR, 'failed to do hgetall: ', err)
      throw(code.REDIS)
    end
    local group = red:array_to_hash(ok)
    if group.state == 'quit' then
      break
    end
    local playerids = cjson.decode(group.member)

    ngx.sleep(5)
    local ok, err = red:lrange(const.KEY_HERO .. '/' .. groupid, 0, -1)
    if not ok then
      ngx.log(ngx.ERR, 'failed to do lrange: ', err)
      throw(code.REDIS)
    end
    local heroids = {}
    for _, v in ipairs(ok) do
      heroids[#heroids + 1] = tonumber(v)
    end
    local resp =
    {
      id = 0,
      event = 'sync',
      args = { heroids = heroids }
    }
    for playerid, _ in pairs(playerids) do
      singlecast(red, playerid, resp)
    end
  end

  local ok, err = red:hgetall(key)
  if not ok then
    ngx.log(ngx.ERR, 'failed to do hgetall: ', err)
    throw(code.REDIS)
  end
  local group = red:array_to_hash(ok)
  local playerids = cjson.decode(group.member)

  local resp =
  {
    id = 0,
    event = 'over'
  }
  for playerid, _ in pairs(playerids) do
    singlecast(red, playerid, resp)
  end

  for playerid, _ in pairs(playerids) do
    local ok, err = red:hdel(const.KEY_PLAYER .. '/' .. playerid, const.KEY_GROUP)
    if not ok then
      ngx.log(ngx.ERR, 'failed to do hdel: ', err)
      throw(code.REDIS)
    end
  end
  local ok, err = red:del(key)
  if not ok then
    ngx.log(ngx.ERR, 'failed to do del: ', err)
    throw(code.REDIS)
  end
  local ok, err = red:del(const.KEY_HERO .. '/' .. groupid)
  if not ok then
    ngx.log(ngx.ERR, 'failed to do del: ', err)
    throw(code.REDIS)
  end
  red:close()
end