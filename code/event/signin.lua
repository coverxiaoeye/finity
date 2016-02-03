local cjson = require('cjson')
local code = require('code')
local throw = require('throw')
local const = require('const')
local config = require('config')
local http = require('resty.http')

--登录事件处理
return function(req, sess, data)
  if sess.id then
    throw(code.SIGNIN_ALREADY)
  end
  local sid = req.args.sid

  --验证sid合法性并得到userid
  local httpc = http:new()
  httpc:set_timeout(config.gate.timeout)
  local ok, err = httpc:connect(config.gate.host, config.gate.port)
  if not ok then
    ngx.log(ngx.ERR, 'failed to new http: ', err)
    throw(code.HTTP)
  end
  local params =
  {
    method = 'POST',
    path = config.gate.uri,
    body = 'sid=' .. sid,
    headers = { ["Content-Type"] = "application/x-www-form-urlencoded" }
  }
  local ret, err = httpc:request(params)
  if not ret then
    ngx.log(ngx.ERR, 'failed to request gate: ', err)
    throw(code.HTTP)
  end
  if ret.status ~= ngx.HTTP_OK then
    ngx.log(ngx.ERR, 'failed to request gate, errcode: ', ret.status)
    throw(code.HTTP)
  end
  local body, err = ret:read_body()
  if not body then
    ngx.log(ngx.ERR, 'failed to request gate: ', err)
    throw(code.HTTP)
  end
  httpc:close()
  local userid = cjson.decode(body).userid

  --获取userid对应的玩家id,没有则自动创建
  local sql = 'SELECT id FROM player WHERE userid = %d'
  local player = data.queryone(sql, userid)
  if not player then
    local sql = 'INSERT INTO player(userid) VALUES(%d)'
    local id = data.insert(sql, userid)
    player = { id = id }
  end

  local kv = sess.kv
  --已存在于全服会话中则抛出异常
  if 1 == kv.call('sismember', const.session(), player.id) then
    throw(code.SIGNIN_ALREADY)
  end
  --添加会全服会话
  kv.call('sadd', const.session(), player.id)

  sess.id = player.id
end