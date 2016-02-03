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

  -- close session
  M.close = function()
    M.closed = true
    if M.kv then
      local playerkey = const.player(M.id)
      local group = M.kv.rawcall('hget', playerkey, 'group')
      if group and group ~= ngx.null then
        local groupkey = const.group(group)
        local member = M.kv.rawcall('hget', groupkey, 'member')
        local ids = codec.dec(member)
        remove(ids, M.id)
        if next(ids) then
          M.kv.rawcall('hmset', groupkey, 'state', 'quit', 'member', codec.enc(ids))
        else
          M.kv.rawcall('del', groupkey)
        end
      end
      M.kv.rawcall('del', playerkey)
      M.kv.rawcall('srem', const.session(), M.id)
    end
    -- TODO logic clean up
  end

  M.singlecast = function(playerid, resp)
    M.kv.call('publish', resp.event .. '/' .. playerid, cjson.encode(resp))
  end

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

  M.broadcast = function(resp)
    local ids = M.kv.call('smembers', const.session())
    for _, v in ipairs(ids) do
      M.singlecast(v, resp)
    end
  end

  -- begin transaction
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

  -- end transaction
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

  -- listen to event
  local function listen()
    -- redis for event listening
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
    -- extract events
    local function events()
      local t = {}
      for k, v in pairs(event) do
        t[#t + 1] = (type(k) == 'number' and v or k) .. '/' .. M.id
      end
      return t
    end

    -- make a thread for event listening
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

  -- start session
  M.start = function()
    -- init semaphore
    local sema, err = semaphore.new()
    if not sema then
      ngx.log(ngx.ERR, 'failed to create semaphore: ', err)
      ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end
    M.sema = sema
    -- register callback of client-closing-connection event
    local ok, err = ngx.on_abort(M.close)
    if not ok then
      ngx.log(ngx.ERR, 'failed to register the on_abort callback: ', err)
      ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end
    -- create socket
    local sock, err = server:new(config.websocket)
    if not sock then
      ngx.log(ngx.ERR, 'failed to new websocket: ', err)
      ngx.exit(ngx.HTTP_CLOSE)
    end
    M.sock = sock
    -- redis for data operation & publishing
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
    -- message loop
    while not M.closed do
      -- TODO idle
      local message, typ, err = M.sock:recv_frame()
      if M.sock.fatal then
        ngx.log(ngx.ERR, 'failed to receive frame: ', err)
        M.close()
        break
      end
      -- message processing
      if typ == 'close' then M.close() break end
      if typ == 'text' then
        local ok, req = pcall(function() return cjson.decode(message) end)
        if not ok then M.close() break end
        local name = req.event
        if not name or not event[name] or (not M.id and name ~= 'signin') then
          M.close()
          break
        end
        -- start transaction
        local db
        if event[name][2] then
          db = txbegin()
          if not db then txend(db) M.close() break end
        end
        local ok, err = pcall(function()
          local func = event[name][1]
          func(req, M, data(db))
        end)
        txend(db, ok)
        -- begin listen event when signin done
        if ok and name == 'signin' and M.id then
          M.t_sub = listen()
          local done, err = M.sema:wait(3) -- wait for redis connection within 3 second at most
          if not done then
            ngx.log(ngx.ERR, 'failed to wait listener start: ', err)
            M.close()
          else
            M.singlecast(M.id, { id = req.id, event = name, args = { id = M.id } })
          end
        end
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
    -- clean up
    if M.t_sub then
      ngx.thread.wait(M.t_sub)
    end
    if M.kv then
      M.kv.red:close()
    end
    if M.sub then
      M.sub:close()
    end
    local bs, err = sock:send_close()
    if not bs then
      ngx.log(ngx.ERR, 'failed to close websocket: ', err)
      ngx.exit(ngx.HTTP_CLOSE)
    end
  end

  return M
end