local code = require('code')
local throw = require('throw')
local const = require('const')

return function(sess)
  -- 3 minutes game, 5 second to sync data
  for i = 1, 36 do
    ngx.sleep(5)
    local ok, err = sess.red:lrange(const.KEY_HEROS .. '/' .. sess.group, 0, -1)
    if not ok then
      ngx.log(ngx.ERR, 'failed to do lrange: ', err)
      throw(code.REDIS)
    end
    local heroids = {}
    for _, v in ipairs(ok) do
      heroids[#heroids + 1] = tonumber(v)
    end
    local resp =
    {
      id = 0,
      event = 'sync',
      args = { heroids = heroids }
    }
    ngx.log(ngx.DEBUG, 'GROUP CAST: sync')
    sess.groupcast(resp)
  end
end