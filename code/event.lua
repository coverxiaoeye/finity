return
{
  ping = require('event.ping'),
  signin = require('event.signin'),
  send = require('event.send'),
  -- events fired by server (without 'fire' function)
  error = { channel = 'self', key = 'error' },
  close = { close = 'self', key = 'close' },
  move = { channel = 'group', key = 'move' },
}
