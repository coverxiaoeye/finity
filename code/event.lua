return
{
  -- server side events
  'error', 'retry', 'sync',
  -- client side events {module, transactional}
  ping = { require('event.ping'), false },
  signin = { require('event.signin'), true },
  match = { require('event.match'), false },
  send = { require('event.send'), false },
}
