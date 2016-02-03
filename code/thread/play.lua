local cjson = require('cjson')
local codec = require('codec')
local redis = require('resty.redis')
local kv = require('kv')
local config = require('config')
local const = require('const')

local function singlecast(kv, playerid, resp)
  kv.call('publish', resp.event .. '/' .. playerid, cjson.encode(resp))
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
  local kv = kv(red)

  -- 3 minutes game, 5 second to sync data
  local groupkey, herokey, ids = const.group(groupid), const.hero(groupid), nil
  while true do
    local ret = kv.call('hgetall', groupkey)
    local group = kv.rawcall('array_to_hash', ret)
    ids = codec.dec(group.member)
    if group.state == 'quit' then
      break
    end

    ngx.sleep(5)
    local ret, heroids = kv.call('lrange', herokey, 0, -1), {}
    for _, v in ipairs(ret) do
      heroids[#heroids + 1] = tonumber(v)
    end
    local resp =
    {
      id = 0,
      event = 'sync',
      args = { heroids = heroids }
    }
    for _, v in pairs(ids) do
      singlecast(kv, v, resp)
    end
  end

  local resp =
  {
    id = 0,
    event = 'over'
  }
  for _, v in pairs(ids) do
    singlecast(kv, v, resp)
  end

  for _, v in pairs(ids) do
    kv.call('hdel', const.player(v), 'group')
  end
  kv.call('del', groupkey)
  kv.call('del', herokey)
  kv.red:close()
end