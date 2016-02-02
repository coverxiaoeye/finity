local cjson = require('cjson')
local code = require('code')
local throw = require('throw')
local const = require('const')
local config = require('config')
local http = require('resty.http')

return function(req, sess, data)
  if sess.id > 0 then
    throw(code.SIGNIN_ALREADY)
  end
  local sid = req.args.sid

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

  local sql = 'SELECT id FROM player WHERE userid = %d'
  local player = data.queryone(sql, userid)
  if not player then
    local sql = 'INSERT INTO player(userid) VALUES(%d)'
    local id = data.insert(sql, userid)
    player = { id = id }
  end
  local ok, err = sess.red:sismember(const.KEY_SESSION, player.id)
  if not ok then
    ngx.log(ngx.ERR, 'failed to do sismember: ', err)
    throw(code.REDIS)
  end
  if ok == 1 then
    throw(code.SIGNIN_ALREADY)
  end
  local ok, err = sess.red:sadd(const.KEY_SESSION, player.id)
  if not ok then
    ngx.log(ngx.ERR, 'failed to do sadd: ', err)
    throw(code.REDIS)
  end
  sess.id = player.id
end