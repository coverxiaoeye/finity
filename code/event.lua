return
{
  --服务器主动通知型事件
  'error', 'retry', 'sync', 'over',
  --客户端请求事件, 第二个参数为是否需要mysql事务支持
  ping = { require('event.ping'), false },
  signin = { require('event.signin'), true },
  match = { require('event.match'), false },
  send = { require('event.send'), false },
}
