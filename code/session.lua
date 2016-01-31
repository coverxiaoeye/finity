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
    sema = nil
  }

  -- close session
  M.close = function()
    M.closed = true
    local ok, err = M.red:srem(const.KEY_SESSION, M.id)
    if not ok then
      ngx.log(ngx.FATAL, 'failed to do srem: ', err)
    end
    local ok, err = M.red:srem(const.KEY_GROUP .. '/' .. M.group, M.id)
    if not ok then
      ngx.log(ngx.FATAL, 'failed to do srem: ', err)
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

  local function mysql_start()
    local my, err = mysql:new()
    if not my then
      ngx.log(ngx.ERR, 'failed to new mysql: ', err)
      return
    end
    my:set_timeout(config.mysql.timeout)
    local ret, err, errno, sqlstate = my:connect(config.mysql.datasource)
    if not ret then
      ngx.log(ngx.ERR, 'failed to connect to mysql: ', err)
      return
    end
    local ret, err, errno, sqlstate = my:query('START TRANSACTION')
    if not ret then
      ngx.log(ngx.ERR, 'failed to start mysql transaction: ', err)
      return
    end
    return my
  end
  local function mysql_end(my, commit)
    if my then
      if commit then
        my:query('COMMIT')
      else
        my:query('ROLLBACK')
      end
      my:set_keepalive(config.mysql.keepalive, config.mysql.poolsize)
    end
  end

  local function onsignin()
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

    local function _listen()
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
    end

    return ngx.thread.spawn(_listen)
  end

  -- start session
  M.start = function()
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

    local sock, err = server:new(config.websocket)
    if not sock then
      ngx.log(ngx.ERR, 'failed to new websocket: ', err)
      ngx.exit(ngx.HTTP_CLOSE)
    end
    M.sock = sock

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
    M.red = red

    local n, s = 0, nil
    while not M.closed do
      local message, typ, err = sock:recv_frame()
      if sock.fatal then
        ngx.log(ngx.ERR, 'failed to receive frame: ', err)
        M.close()
        break
      end
      -- kick idle connection when idle for 5 times (hard-coded)
      if not message and string.find(err, ': timeout', 1, true) then
        n = n + 1
        if n >= 5 then
          ngx.log(ngx.ERR, 'idle connection')
          M.close()
          break
        end
      end
      if typ == 'close' then
        M.close()
        break
      end
      if typ == 'text' then
        n = 0

        local my = mysql_start()
        if not my then
          mysql_end(my, false)
          M.close()
          break
        end
        local eventid, eventname, args
        local ok, ret = pcall(function()
          local r = cjson.decode(message)
          eventid, eventname, args = r.id, r.event, r.args
          if not eventname or not event[eventname] or not event[eventname].fire or (M.id == 0 and eventname ~= 'signin') then
            throw(code.INVALID_EVENT)
          end
          return event[eventname].fire(args, M, data(my))
        end)
        mysql_end(my, ok)

        if ok and eventname == 'signin' and M.id > 0 then
          s = onsignin()
          if not s then
            M.close()
          else
            local done, err = sema:wait(1) -- wait for redis connection within 1 second at most
            if not done then
              ngx.log(ngx.ERR, 'failed to wait listener start: ', ret)
              M.close()
            end
          end
        end

        local resp = { id = eventid, event = eventname }
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
          if not done then
            M.close()
          end
        end
      end
    end

    -- clean up
    if s then
      local ok, res = ngx.thread.wait(s)
      if not ok then
        ngx.log(ngx.ERR, 'failed to wait listener: ', res)
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