# 摘要
<pre>
Websocket游戏开发模板,开发语言为Lua,运行环境包括:
<a href="http://openresty.org" target="_blank">OpenResty</a> (version: 1.9.7.2+)
<a href="http://redis.io" target="_blank">Redis</a> (version: 2.0.0+)
<a href="http://mysql.com" target="_blank">Mysql</a> (version: 5.5+).
</pre>

## 客户端发送数据格式(JSON)
<pre>
{"id": xxx, "event": "xxx", "args": xxx}
<b>id</b>: 整型, 事件ID (建议发送, 服务器应做同样的返回以方便客户端做对应)
<b>event</b>: 字符, 事件名称
<b>args</b>: 任意, 事件的描述参数, 由事件本身决定, 可为null
</pre>

## 服务器广播数据格式(JSON)
<pre>
{"id": xxx, "event": "xxx", "args": xxx, "err": xxx}
<b>id</b>: 整型, 事件ID, 跟客户端发送的事件ID对应; 服务器主动广播的事件, 此值为0
<b>event</b>: 字符, 事件名称
<b>args</b>: 任意, 事件的描述参数, 由事件本身决定, 可为null
<b>code</b>: 整型, 错误码, 当event为'error'是有此字段
</pre>

## 错误码列表
<pre>
UNKNOWN = -1, --未知错误(一般为程序BUG)
MYSQL = 1, --mysql操作异常
REDIS = 2, --redis操作异常
HTTP = 3, --http访问异常

LOCK = 1001, --mysql数据并发
ILLEGAL = 2000, --非法访问,请求不合法(一般为程序BUG)
SIGNIN_ALREADY = 2001, --已登录
</pre>
