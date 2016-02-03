return function(req, sess)
  sess.singlecast(sess.id, { id = req.id, event = req.event, args = req.args })
end