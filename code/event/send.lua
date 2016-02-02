local code = require('code')
local throw = require('throw')
local const = require('const')

return function(req, sess)
  local heroid = req.args.heroid
  local ok, err = sess.red:rpush(const.KEY_HEROS .. '/' .. sess.group, heroid)
  if not ok then
    ngx.log(ngx.ERR, 'failed to do rpush: ', err)
    throw(code.REDIS)
  end
  local resp =
  {
    id = req.id,
    event = req.event,
    args = req.args
  }
  sess.singlecast(sess.id, resp)
  local resp =
  {
    id = 0,
    event = req.event,
    args = { playerid = sess.id, heroid = heroid }
  }
  sess.groupcast(resp)
end