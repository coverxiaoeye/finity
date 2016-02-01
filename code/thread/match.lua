-- TODO match demo
return function(sess)
  for i = 1, 100 do
    if sess.closed then
      break
    end
    local resp = { id = 0, event = 'move', args = { seq = i } }
    sess.dispatch(resp)
    ngx.sleep(1)
  end
end