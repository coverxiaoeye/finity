return
{
  UNKNOWN = -1, --未知错误(一般为程序BUG)
  MYSQL = 1, --mysql操作异常
  REDIS = 2, --redis操作异常
  HTTP = 3, --http访问异常

  LOCK = 1001, --mysql数据并发
  ILLEGAL = 2000, --非法访问,请求不合法(一般为程序BUG)
  SIGNIN_ALREADY = 2001, --已登录
}
