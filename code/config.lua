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
    host = 'localhost',
    port = 80,
<<<<<<< HEAD
    uri = '/s/sign/verify'
=======
    uri = '/user/verify'
>>>>>>> 9b19a821c1a2e8e0d2cd1e5178671a5f08914bf5
  }
}

