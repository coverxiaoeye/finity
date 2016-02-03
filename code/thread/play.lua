local cjson = require('cjson')
local codec = require('codec')
local redis = require('resty.redis')
local kv = require('kv')
local config = require('config')
local const = require('const')

--单播
local function singlecast(kv, playerid, resp)
  kv.call('publish', resp.event .. '/' .. playerid, cjson.encode(resp))
end

--游戏线程
return function(premature, groupid)
  --服务器正在重启等情况
  --TODO 游戏中的玩家踢出
  if premature then
    return
  end

  --建立数据处理的redis连接(全局)并包装为kv
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

  --3分钟结束,每5秒组播战场中的英雄
  local groupkey, herokey, ids = const.group(groupid), const.hero(groupid), nil
  while true do
    --检查游戏是否为quit状态(有玩家退出)
    local ret = kv.call('hgetall', groupkey)
    local group = kv.rawcall('array_to_hash', ret)
    ids = codec.dec(group.member)
    if group.state == 'quit' then
      break
    end
    ngx.sleep(5)
    --获取所有战场中的英雄
    local ret, heroids = kv.call('lrange', herokey, 0, -1), {}
    for _, v in ipairs(ret) do
      heroids[#heroids + 1] = tonumber(v)
    end
    --组播同步战场英雄的sync消息
    local resp = { id = 0, event = 'sync', args = { heroids = heroids } }
    for _, v in pairs(ids) do
      singlecast(kv, v, resp)
    end
  end

  --游戏完成或中断后组播over消息
  local resp = { id = 0, event = 'over' }
  for _, v in pairs(ids) do
    singlecast(kv, v, resp)
  end

  --清除组内玩家所在游戏组信息
  for _, v in pairs(ids) do
    kv.call('hdel', const.player(v), 'group')
  end
  --删除游戏组和战场英雄
  kv.call('del', groupkey)
  kv.call('del', herokey)
  --关闭redis
  kv.red:close()
end