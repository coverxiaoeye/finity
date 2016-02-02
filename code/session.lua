return function()
  local cjson = require('cjson')
  local server = require('resty.websocket.server')
  local mysql = require('resty.mysql')
  local redis = require('resty.redis')
  local semaphore = require('ngx.semaphore')

  local code = require('code')
  local throw = require('throw')
  local config = require('config')
  local data = require('data')
  local event = require('event')
  local const = require('const')

  local M =
  {
    id = 0,
    group = 0,
    closed = false,
    sock = nil,
    sub = nil,
    red = nil,
    sema = nil,
    t_sub = nil,
    t_match = nil,
  }

  -- close session
  M.close = function()
    M.closed = true
    if M.red then
      local ok, err = M.red:srem(const.KEY_SESSION, M.id)
      if not ok then
        ngx.log(ngx.FATAL, 'failed to do srem: ', err)
      end
      local ok, err = M.red:srem(const.KEY_GROUP .. '/' .. M.group, M.id)
      if not ok then
        ngx.log(ngx.FATAL, 'failed to do srem: ', err)
      end
    end
    -- TODO logic clean up
  end

  -- dispatch event
  M.dispatch = function(resp)
    local name, keys = resp.event, {}
    if event[name].channel == 'self' then
      keys[#keys + 1] = event[name].key .. '/' .. M.id
    elseif event[name].channel == 'all' then
      resp.id = 0
      keys[#keys + 1] = event[name].key
    elseif event[name].channel == 'group' then
      resp.id = 0
      local ids, err = M.red:smembers(const.KEY_GROUP .. '/' .. M.group)
      if not ids then
        ngx.log(ngx.ERR, 'failed to read members: ', err)
        throw(code.REDIS)
      end
      for _, id in ipairs(ids) do
        keys[#keys + 1] = event[name].key .. '/' .. id
      end
    end
    for _, key in ipairs(keys) do
      local ok, err = M.red:publish(key, cjson.encode(resp))
      if not ok then
        ngx.log(ngx.ERR, 'failed to publish: ', err)
        throw(code.REDIS)
      end
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
    -- extract channels
    local function channel()
      local t = {}
      for _, v in pairs(event) do
        if v.channel == 'self' or v.channel == 'group' then
          t[#t + 1] = v.key .. '/' .. M.id
        elseif v.channel == 'all' then
          t[#t + 1] = v.key
        end
      end
      return t
    end
    -- make a thread for event listening
    return ngx.thread.spawn(function()
      M.sub:subscribe(unpack(channel()))
      M.sema:post(1)
      while not M.closed do
        local ret, err = M.sub:read_reply()
        if not ret and err ~= 'timeout' then
          ngx.log(ngx.ERR, 'failed to read reply: ', err)
          M.close()
        end
        if ret and ret[1] == 'message' then
          if ret[2] == 'close/' .. M.id then
            M.close()
          else
            local bs, err = M.sock:send_text(ret[3])
            if not bs then
              ngx.log(ngx.ERR, 'failed to send text: ', err)
              M.close()
            end
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
    M.red = red
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
        local ok, ret = pcall(function() return cjson.decode(message) end)
        if not ok then M.close() break end
        local id, name, args = ret.id, ret.event, ret.args
        if not name or not event[name] or not event[name].fire or (M.id == 0 and name ~= 'signin') then
          M.close()
          break
        end
        -- start transaction only if tx attribute set
        local db
        if event[name].tx then
          db = txbegin()
          if not db then txend(db, false) M.close() break end
        end
        local ok, ret = pcall(function() return event[name].fire(args, M, data(db)) end)
        txend(db, ok)
        -- begin listen event when signin done
        if ok and name == 'signin' and M.id > 0 then
          M.t_sub = listen()
          local done, err = M.sema:wait(1) -- wait for redis connection within 1 second at most
          if not done then
            ngx.log(ngx.ERR, 'failed to wait listener start: ', ret)
            M.close()
          end
        end
        -- dispatch event
        local resp = { id = id, event = name }
        if not ok then
          ngx.log(ngx.ERR, 'error occurred: ', ret)
          local idx = string.find(ret, '{', 1, true)
          local errcode = idx and loadstring('return ' .. string.sub(ret, idx))().err or code.UNKNOWN
          ngx.log(ngx.ERR, 'failed to fire event: ', message, ', errcode: ', errcode)
          if errcode < 1000 then
            M.close()
          else
            resp.event, resp.err = 'error', errcode
          end
        else
          resp.args = ret
        end

        if not M.closed then
          local done = pcall(function() M.dispatch(resp) end)
          if not done then M.close() end
        end
      end
    end
    -- clean up
    if M.t_sub then
      local ok, res = ngx.thread.wait(M.t_sub)
      if not ok then
        ngx.log(ngx.ERR, 'failed to wait sub thread: ', res)
      end
    end
    if M.t_match then
      local ok, res = ngx.thread.wait(M.t_match)
      if not ok then
        ngx.log(ngx.ERR, 'failed to wait match thread: ', res)
      end
    end
    if M.red then
      M.red:close()
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