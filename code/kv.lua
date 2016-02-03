local code = require('code')
local throw = require('throw')

return function(r)
  local M = { red = r }

  M.call = function(cmd, ...)
    local ok, err = M.red[cmd](M.red, ...)
    if not ok then
      ngx.log(ngx.ERR, 'failed to call redis command: ', cmd, err)
      throw(code.REDIS)
    end
    return ok
  end

  M.rawcall = function(cmd, ...)
    local ok, err = M.red[cmd](M.red, ...)
    if not ok then
      ngx.log(ngx.ERR, 'failed to call redis command: ', cmd, ...)
    end
    return ok, err
  end

  return M
end
