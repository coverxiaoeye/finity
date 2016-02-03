local cjson = require('cjson')
local codec = require('codec')
local remove = require('remove')
local server = require('resty.websocket.server')
local mysql = require('resty.mysql')
local redis = require('resty.redis')
local semaphore = require('ngx.semaphore')

local code = require('code')
local config = require('config')
local data = require('data')
local kv = require('kv')
local event = require('event')
local const = require('const')

--创建一个会话
return function()
  local M =
  {
    id = nil,
    closed = false,
    sock = nil,
    kv = nil,
    sub = nil,
    sema = nil,
    t_sub = nil,
  }

  --设置会话为关闭状态, 清理逻辑相关数据
  M.close = function()
    M.closed = true
    if M.kv then
      local playerkey = const.player(M.id)
      local group = M.kv.rawcall('hget', playerkey, 'group')
      --若会话在某个组中,则从组中删除本会话
      if group and group ~= ngx.null then
        local groupkey = const.group(group)
        local member = M.kv.rawcall('hget', groupkey, 'member')
        local ids = codec.dec(member)
        remove(ids, M.id)
        --组中还有其他会话则改组状态为"有人退出",否则直接删除该组
        if next(ids) then
          M.kv.rawcall('hmset', groupkey, 'state', 'quit', 'member', codec.enc(ids))
        else
          M.kv.rawcall('del', groupkey)
        end
      end
      --删除会话信息并从全服会话列表中清除
      M.kv.rawcall('del', playerkey)
      M.kv.rawcall('srem', const.session(), M.id)
    end
    --TODO 其他清理
  end

  --单播
  M.singlecast = function(playerid, resp)
    M.kv.call('publish', resp.event .. '/' .. playerid, cjson.encode(resp))
  end

  --组内广播
  M.groupcast = function(resp)
    local group = M.kv.call('hget', const.player(M.id), 'group')
    if group == ngx.null then
      return
    end
    local member = M.kv.call('hget', const.group(group), 'member')
    local ids = cjson.decode(member)
    for _, v in ipairs(ids) do
      M.singlecast(v, resp)
    end
  end

  --全服广播
  M.broadcast = function(resp)
    local ids = M.kv.call('smembers', const.session())
    for _, v in ipairs(ids) do
      M.singlecast(v, resp)
    end
  end

  --开始mysql事务
  local function txbegin()
    local db, err = mysql:new()
    if not db then
      ngx.log(ngx.ERR, 'failed to new mysql: ', err)
      return
    end
    db:set_timeout(config.mysql.timeout)
    local ret, err = db:connect(config.mysql.datasource)
    if not ret then
      ngx.log(ngx.ERR, 'failed to connect to mysql: ', err)
      return
    end
    local ret, err = db:query('START TRANSACTION')
    if not ret then
      ngx.log(ngx.ERR, 'failed to start mysql transaction: ', err)
      return
    end
    return db
  end

  --结束mysql事务
  local function txend(db, commit)
    if db then
      if commit then
        db:query('COMMIT')
      else
        db:query('ROLLBACK')
      end
      db:set_keepalive(config.mysql.keepalive, config.mysql.poolsize)
    end
  end

  --创建单独的redis连接用于监听订阅信息
  local function listen()
    local red, err = redis:new()
    if not red then
      ngx.log(ngx.ERR, 'failed to new sub redis: ', err)
      return
    end
    red:set_timeout(config.redis.timeout)
    local ok, err = red:connect(config.redis.host)
    if not ok then
      ngx.log(ngx.ERR, 'failed to connect to sub redis: ', err)
      return
    end
    M.sub = red
    --读取所有订阅事件
    local function events()
      local t = {}
      for k, v in pairs(event) do
        t[#t + 1] = (type(k) == 'number' and v or k) .. '/' .. M.id
      end
      return t
    end

    --开新线程监听订阅,主循环结束时要等待其结束
    return ngx.thread.spawn(function()
      M.sub:subscribe(unpack(events()))
      M.sema:post(1)
      while not M.closed do
        local ret, err = M.sub:read_reply()
        if not ret and err ~= 'timeout' then
          ngx.log(ngx.ERR, 'failed to read reply: ', err)
          M.close()
        end
        if ret and ret[1] == 'message' then
          local bs, err = M.sock:send_text(ret[3])
          if not bs then
            ngx.log(ngx.ERR, 'failed to send text: ', err)
            M.close()
          end
        end
      end
    end)
  end

  --建立连接开启会话
  M.start = function()
    --线程调度器,用于确认当订阅线程准备好时才可以发布事件
    local sema, err = semaphore.new()
    if not sema then
      ngx.log(ngx.ERR, 'failed to create semaphore: ', err)
      ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end
    M.sema = sema
    --当客户端意外关闭连接时的回调
    local ok, err = ngx.on_abort(M.close)
    if not ok then
      ngx.log(ngx.ERR, 'failed to register the on_abort callback: ', err)
      ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end
    --创建socket
    local sock, err = server:new(config.websocket)
    if not sock then
      ngx.log(ngx.ERR, 'failed to new websocket: ', err)
      ngx.exit(ngx.HTTP_CLOSE)
    end
    M.sock = sock
    --创建数据操作的redis连接并包装为kv
    local red, err = redis:new()
    if not red then
      ngx.log(ngx.ERR, 'failed to new redis: ', err)
      ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end
    red:set_timeout(config.redis.timeout)
    local ok, err = red:connect(config.redis.host)
    if not ok then
      ngx.log(ngx.ERR, 'failed to connect to redis: ', err)
      ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end
    M.kv = kv(red)
    --主线程循环处理消息
    while not M.closed do
      --TODO 超时连接处理, 通过判定err为timeout
      local message, typ, err = M.sock:recv_frame()
      if M.sock.fatal then
        ngx.log(ngx.ERR, 'failed to receive frame: ', err)
        M.close()
        break
      end
      if typ == 'close' then
        M.close()
        break
      elseif typ == 'text' then
        local ok, req = pcall(function() return cjson.decode(message) end)
        --解析消息失败
        if not ok then
          M.close()
          break
        end
        local name = req.event
        --消息不存在或第一个事件不是登录请求
        if not name or not event[name] or (not M.id and name ~= 'signin') then
          M.close()
          break
        end
        --判断事件是否需要开启mysql事务支持
        local db
        if event[name][2] then
          db = txbegin()
          --开启事务失败则关闭会话
          if not db then
            txend(db)
            M.close()
            break
          end
        end
        local ok, err = pcall(function()
          local func = event[name][1]
          func(req, M, data(db))
        end)
        txend(db, ok)
        --登录事件成功处理后开启redis订阅
        if ok and name == 'signin' and M.id then
          M.t_sub = listen()
          local done, err = M.sema:wait(3) --等待订阅成功,如果3秒内未成功,则关闭会话
          if not done then
            ngx.log(ngx.ERR, 'failed to wait listener start: ', err)
            M.close()
          else
            --登录成功后单播登录成功的消息, 不能放在signin.lua里处理(那时订阅还未完成)
            M.singlecast(M.id, { id = req.id, event = name, args = { id = M.id } })
          end
        end
        --逻辑异常的处理
        if not ok then
          ngx.log(ngx.ERR, 'error occurred: ', err)
          local idx = string.find(err, '{', 1, true)
          local errcode = idx and loadstring('return ' .. string.sub(err, idx))().err or code.UNKNOWN
          ngx.log(ngx.ERR, 'failed to fire event: ', message, ', errcode: ', errcode)
          if errcode < 1000 or errcode == code.SIGNIN_ALREADY then
            M.close()
          else
            M.singlecast(M.id, { id = 0, event = 'error', args = { code = errcode } })
          end
        end
      end
    end
    --主循环结束后的清理
    if M.t_sub then
      ngx.thread.wait(M.t_sub) --待订阅线程结束
    end
    if M.kv then
      M.kv.red:close() --关闭数据操作的redis连接
    end
    if M.sub then
      M.sub:close() --关闭订阅redis连接
    end
    local bs, err = sock:send_close() --发送关闭事件
    if not bs then
      ngx.log(ngx.ERR, 'failed to close websocket: ', err)
      ngx.exit(ngx.HTTP_CLOSE)
    end
  end

  return M
end