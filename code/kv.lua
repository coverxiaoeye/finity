local code = require('code')
local throw = require('throw')

--redis包装
return function(r)
  local M = { red = r }

  --执行redis命令并做异常处理
  M.call = function(cmd, ...)
    local ok, err = M.red[cmd](M.red, ...)
    if not ok then
      ngx.log(ngx.ERR, 'failed to call redis command: ', cmd, err)
      throw(code.REDIS)
    end
    return ok
  end

  --原生执行redis命令,不做异常处理
  M.rawcall = function(cmd, ...)
    local ok, err = M.red[cmd](M.red, ...)
    if not ok then
      ngx.log(ngx.ERR, 'failed to call redis command: ', cmd, ...)
    end
    return ok, err
  end

  return M
end
