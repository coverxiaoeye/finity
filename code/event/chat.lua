local redis = require('resty.redis')

local M = { channel = 'all' }

M.fire = function(args, sess)
  local red, err = redis:new()
  if not red then
    ngx.log(ngx.ERR, 'failed to new redis: ', err)
    sess.close()
  end
  red:set_timeout(3000)
  local ok, err = red:connect('unix:/usr/local/var/run/redis.sock')
  if not ok then
    ngx.log(ngx.ERR, 'failed to connect to redis: ', err)
    sess.close()
  end
  local ok, err = red:publish('chat', args)
  if not ok then
    ngx.log(ngx.ERR, 'failed to publish to redis: ', err)
    sess.close()
  end
  red:set_keepalive(6000, 100)
end

return M