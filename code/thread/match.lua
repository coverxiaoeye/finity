-- TODO match demo
return function(sess)
  for i = 1, 100 do
    local resp = {id = 0, event = 'move', args = {seq = i}}
    sess.dispatch(resp)
    ngx.sleep(1)
  end
end