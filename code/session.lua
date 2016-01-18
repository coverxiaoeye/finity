return function()
  local server = require('resty.websocket.server')
  local redis = require('resty.redis')
  local cjson = require('cjson')
  local event = require('event')

  local M =
  {
    id = 0,
    closed = false,
  }

  function M.close()
    M.closed = true
    -- TODO other cleanups
  end

  function M.start()
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
    local ok, err = sub:connect('unix:/usr/local/var/run/redis.sock')
    if not ok then
      ngx.log(ngx.ERR, 'failed to connect to sub redis: ', err)
      ngx.exit(444)
      return
    end

    local function channel()
      local t = {}
      for k, v in pairs(event) do
        if v.channel == 'self' then
          table.insert(t, k .. '/' .. M.id)
        elseif v.channel == 'all' then
          table.insert(t, k)
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
              -- TODO close session?
            end
          else
            local bs, err = sock:send_text(ret[3])
            if not bs then
              ngx.log(ngx.ERR, 'failed to send text: ', err)
              -- TODO close session?
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
          local evt, args
          local ok = pcall(function()
            if typ == 'ping' then
              evt, args = 'ping', {}
            else
              local r = cjson.decode(message)
              evt, args = r.event, r.args
            end
            local m = event[evt]
            m.fire(args, M)
          end)
          if not ok then
            ngx.log(ngx.ERR, 'failed to call function: ', evt or '', message)
            -- TODO error handling
          end
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