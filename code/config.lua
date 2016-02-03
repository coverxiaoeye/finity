return
{
  debug = true,

  websocket =
  {
    timeout = 3000,
    max_payload_len = 8192
  },

  mysql =
  {
    timeout = 1000,
    keepalive = 6000,
    poolsize = 64,
    datasource =
    {
      host = '127.0.0.1',
      port = 3306,
      database = 'finity',
      user = 'finity',
      password = 'finity'
    }
  },

  redis =
  {
    timeout = 1000,
    keepalive = 6000,
    poolsize = 64,
    host = 'unix:/usr/local/var/run/redis-finity.sock'
  },

  gate =
  {
    timeout = 3000,
    host = 'gate.weiyouba.cn',
    port = 80,
    uri = '/user/verify'
  }
}

