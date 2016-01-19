return
{
  debug = true,
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
    host = 'unix:/usr/local/var/run/redis.sock'
  }
}

