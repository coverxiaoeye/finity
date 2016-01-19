return function()
  local cjson = require('cjson')
  local server = require('resty.websocket.server')
  local mysql = require('resty.mysql')
  local redis = require('resty.redis')
  local config = require('config')
  local data = require('data')
  local event = require('event')

  local M =
  {
    id = 0,
    closed = false,
  }

  -- close session
  M.close = function()
    M.closed = true
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
  local function after(my, red, commit, keep)
    if my then
      if commit then
        my:query('COMMIT')
      else
        my:query('ROLLBACK')
      end
      if keep then
        my:set_keepalive(config.mysql.keepalive, config.mysql.poolsize)
      else
        my:close()
      end
    end
    if red then
      if keep then
        red:set_keepalive(config.redis.keepalive, config.redis.poolsize)
      else
        red:close()
      end
    end
  end

  -- start session
  M.start = function()
    M.id = ngx.var.connection

    -- register callback of client-closing-connection event
    local ok, err = ngx.on_abort(M.close)
    if not ok then
      ngx.log(ngx.ERR, 'failed to register the on_abort callback: ', err)
      ngx.exit(500)
    end

    local sock, err = server:new({ timeout = 3000, max_payload_len = 8192 })
    if not sock then
      ngx.log(ngx.ERR, 'failed to new websocket: ', err)
      ngx.exit(444)
      return
    end

    -- BEGIN init subscribe listener
    local sub, err = redis:new()
    if not sub then
      ngx.log(ngx.ERR, 'failed to new sub redis: ', err)
      ngx.exit(444)
      return
    end
    sub:set_timeout(3000)
    local ok, err = sub:connect(config.redis.host)
    if not ok then
      ngx.log(ngx.ERR, 'failed to connect to sub redis: ', err)
      ngx.exit(444)
      return
    end

    -- extract channels
    local function channel()
      local t = { 'error/' .. M.id }
      for _, v in pairs(event) do
        if v.channel == 'self' then
          table.insert(t, v.key .. '/' .. M.id)
        elseif v.channel == 'all' then
          table.insert(t, v.key)
        end
      end
      return t
    end

    local function listener()
      local cs = channel()
      sub:subscribe(unpack(cs))

      -- BEGIN subscribe reading (nonblocking)
      while not M.closed do
        local ret, err = sub:read_reply()
        if not ret and err ~= 'timeout' then
          M.close()
          return
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

      sub:close()
      -- END subscribe reading (nonblocking)
    end

    local thread = ngx.thread.spawn(listener)
    -- END init subscribe listener

    -- BEGIN socket reading (nonblocking)
    while not M.closed do
      local message, typ, err = sock:recv_frame()
      if sock.fatal then
        ngx.log(ngx.ERR, 'failed to receive frame: ', err)
        M.close()
      end
      if message then
        if typ == 'close' then
          M.close()
        elseif typ == 'ping' or typ == 'text' then
          local keep, my, red = before()

          -- BEGIN event processing
          local commit = false
          if keep then
            local evt, args
            local ok, ret = pcall(function()
              if typ == 'ping' then
                evt, args = 'ping', '1'
              else
                local r = cjson.decode(message)
                evt, args = r.event, r.args
              end
              local ret = event[evt].fire(args, M, data(my), red)
              return ret
            end)
            commit = ok

            -- error handling
            if not ok then
              ngx.log(ngx.ERR, 'failed to call function: ', evt or '', message)
              local idx = string.find(ret, '{')
              local exception
              if idx then
                exception = loadstring('return ' .. string.sub(ret, idx))()
              else
                exception = { code = -1 }
              end
              local ok, err = red:publish('error/' .. M.id, cjson.encode(exception))
              if not ok then
                ngx.log(ngx.ERR, 'failed to publish event: ', err)
                keep = false
                M.close()
              end
            elseif ret then
              -- publish event to specified channel
              if event[evt].channel == 'self' then
                local ok, err = red:publish(event[evt].key .. '/' .. M.id, ret)
                if not ok then
                  ngx.log(ngx.ERR, 'failed to publish event: ', err)
                  keep = false
                  M.close()
                end
              elseif event[evt].channel == 'all' then
                local ok, err = red:publish(event[evt].key, ret)
                if not ok then
                  ngx.log(ngx.ERR, 'failed to publish event: ', err)
                  keep = false
                  M.close()
                end
              end
            end
          end
          -- END event processing

          after(my, red, commit, keep)
        end
      end
    end
    -- END socket reading (nonblocking)

    local bs, err = sock:send_close()
    if not bs then
      ngx.log(ngx.ERR, 'failed to close websocket: ', err)
      ngx.exit(444)
    end
  end

  return M
end