return function()
  local cjson = require('cjson')
  local server = require('resty.websocket.server')
  local mysql = require('resty.mysql')
  local redis = require('resty.redis')

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
  }

  -- close session
  M.close = function()
    M.closed = true

    if M.id > 0 then
      local ok, red = pcall(function()
        local red, err = redis:new()
        if not red then
          ngx.log(ngx.ERR, 'failed to new redis: ', err)
          throw(code.REDIS)
        end
        red:set_timeout(config.redis.timeout)
        local ok, err = red:connect(config.redis.host)
        if not ok then
          ngx.log(ngx.ERR, 'failed to connect to redis: ', err)
          throw(code.REDIS)
        end
        local ok, err = red:srem(const.KEY_SESSION, M.id)
        if not ok then
          ngx.log(ngx.ERR, 'failed to do srem: ', err)
          throw(code.REDIS)
        end
        return red
      end)
      if not ok then
        ngx.log(ngx.FATAL, 'failed to remove session (' .. M.id .. ')')
      end
      if red then
        red:close()
      end
    end
    -- TODO other cleanups
  end

  -- before event processing
  local function before()
    local my, err = mysql:new()
    if not my then
      ngx.log(ngx.ERR, 'failed to new mysql: ', err)
      return false
    end
    my:set_timeout(config.mysql.timeout)
    local ret, err, errno, sqlstate = my:connect(config.mysql.datasource)
    if not ret then
      ngx.log(ngx.ERR, 'failed to connect to mysql: ', err)
      return false
    end
    local ret, err, errno, sqlstate = my:query('START TRANSACTION')
    if not ret then
      ngx.log(ngx.ERR, 'failed to start mysql transaction: ', err)
      return false
    end

    local red, err = redis:new()
    if not red then
      ngx.log(ngx.ERR, 'failed to new redis: ', err)
      return false
    end
    red:set_timeout(config.redis.timeout)
    local ok, err = red:connect(config.redis.host)
    if not ok then
      ngx.log(ngx.ERR, 'failed to connect to redis: ', err)
      return false
    end
    return true, my, red
  end

  -- after event processing
  local function after(my, red, commit)
    if my then
      if commit then
        my:query('COMMIT')
      else
        my:query('ROLLBACK')
      end
      my:set_keepalive(config.mysql.keepalive, config.mysql.poolsize)
    end
    if red then
      red:set_keepalive(config.redis.keepalive, config.redis.poolsize)
    end
  end

  -- dispatch event
  local function dispatch(evt, ret, red)
    local keys = {}
    if evt == 'error' then
      keys[#keys + 1] = 'error/' .. M.id
    elseif event[evt].channel == 'self' then
      keys[#keys + 1] = event[evt].key .. '/' .. M.id
    elseif event[evt].channel == 'all' then
      keys[#keys + 1] = event[evt].key
    elseif event[evt].channel == 'group' then
      local ids, err = red:lrange('group/' .. M.group, 0, -1)
      if not ids then
        ngx.log(ngx.ERR, 'failed to read members: ', err)
        return
      end
      for _, id in ipairs(ids) do
        keys[#keys + 1] = event[evt].key .. '/' .. id
      end
    end
    if next(keys) then
      local json = cjson.encode(ret)
      for _, key in ipairs(keys) do
        local ok, err = red:publish(event[evt].key .. '/' .. M.id, json)
        if not ok then
          ngx.log(ngx.ERR, 'failed to publish: ', err)
          return
        end
      end
    end
    return true
  end

  -- listen event
  local function listen(sock)
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

    -- extract channels
    local function channel()
      local t = { 'error/' .. M.id }
      for _, v in pairs(event) do
        if v.channel == 'self' or v.channel == 'group' then
          table.insert(t, v.key .. '/' .. M.id)
        elseif v.channel == 'all' then
          table.insert(t, v.key)
        end
      end
      return t
    end

    local function _listen()
      local cs = channel()
      red:subscribe(unpack(cs))

      -- BEGIN subscribe reading (nonblocking)
      while not M.closed do
        local ret, err = red:read_reply()
        if not ret and err ~= 'timeout' then
          ngx.log(ngx.ERR, 'failed to read reply: ', err)
          M.close()
        end
        if ret and ret[1] == 'message' then
          if ret[2] == 'ping/' .. M.id then
            local bs, err = sock:send_pong()
            if not bs then
              ngx.log(ngx.ERR, 'failed to send pong: ', err)
              M.close()
            end
          else
            local bs, err = sock:send_text(ret[3])
            if not bs then
              ngx.log(ngx.ERR, 'failed to send text: ', err)
              M.close()
            end
          end
        end
      end
      red:close()
      -- END subscribe reading (nonblocking)
    end

    return ngx.thread.spawn(_listen)
  end

  -- start session
  M.start = function()
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

    -- BEGIN socket reading (nonblocking)
    local n, listener = 0, nil
    while not M.closed do
      local message, typ, err = sock:recv_frame()
      if sock.fatal then
        ngx.log(ngx.ERR, 'failed to receive frame: ', err)
        M.close()
      end
      -- kick unauthorized connection when idle 5 times (hard-coded)
      if not message and M.id == 0 and string.find(err, ': timeout', 1, true) then
        n = n + 1
        if n >= 5 then
          ngx.log(ngx.ERR, 'unauthorized connection')
          M.close()
        end
      end

      if typ == 'close' then
        M.close()
      elseif typ == 'ping' or typ == 'text' then
        -- ensure first event to be 'signin'
        if M.id == 0 then
          local passed = false
          if typ == 'text' then
            local ok, ret = pcall(function() return cjson.decode(message) end)
            if ok and ret.event == 'signin' then
              passed = true
            end
          end
          if not passed then
            M.close()
            break
          end
        end

        local ok, my, red = before()
        if not ok then
          after(my, red, false)
          M.close()
          break
        end

        -- BEGIN event processing
        local evt, args
        local ok, ret = pcall(function()
          if typ == 'ping' then
            evt, args = 'ping', '1'
          else
            local r = cjson.decode(message)
            evt, args = r.event, r.args
          end
          if not evt or not event[evt] then
            throw(code.INVALID_EVENT)
          end
          return event[evt].fire(args, M, data(my), red)
        end)

        -- init listener
        if ok and evt == 'signin' and M.id > 0 then
          listener = listen(sock)
          if not listener then
            M.close()
          end
        end

        -- error handling
        if not ok then
          local idx, ex = string.find(ret, '{', 1, true)
          if idx then
            ex = loadstring('return ' .. string.sub(ret, idx))()
          else
            ex = { err = -1 }
          end
          ngx.log(ngx.ERR, 'failed to fire event: ', message, ', errcode: ', ex.err)

          if ex.code == code.SIGNIN_ALREADY or ex.code == code.SIGNIN_UNAUTH then
            M.close()
            ret = nil
          else
            evt, ret = 'error', ex
          end
        end

        if ret then
          local ok = dispatch(evt, ret, red)
          if not ok then
            M.close()
          end
        end
        -- END event processing

        after(my, red, ok)
      end
    end
    -- END socket reading (nonblocking)

    if listener then
      local ok, res = ngx.thread.wait(listener)
      if not ok then
        ngx.log(ngx.ERR, 'failed to wait listener: ', res)
      end
    end

    local bs, err = sock:send_close()
    if not bs then
      ngx.log(ngx.ERR, 'failed to close websocket: ', err)
      ngx.exit(ngx.HTTP_CLOSE)
    end
  end

  return M
end