# Description
<pre>
A websocket game server template running on
<a href="http://openresty.org" target="_blank">OpenResty</a> (version: 1.9.7.2+)
<a href="http://redis.io" target="_blank">Redis</a> (version: 2.0.0+)
Mysql (version: 5.5+).
</pre>

## Request json format
<pre>
FORMAT: {"id": xxx, "event": "xxx", "args": xxx}
* <b>id</b>: integer, client specified event id which will be returned unchanged.
* <b>event</b>: string, event name, such as 'signin', 'ping', etc.
* <b>args</b>: any, arguments of this event, <b>NULLABLE</b>.
</pre>

## Broadcast json format
<pre>
FORMAT: {"id": xxx, "event": "xxx", "args": xxx, "err": xxx}
* <b>id</b>: integer, client specified event id or <b>0</b> on broadcasting.
* <b>event</b>: string, event name, such as 'signin', 'ping', etc.
* <b>args</b>: any, arguments of this event, <b>NULLABLE</b>.
* <b>code</b>: integer, error code, <b>NULLABLE</b> (only when event == 'error').
</pre>

## Error code
<pre>
UNKNOWN = -1, -- unknown error (bugs, json decoding, etc.)
MYSQL = 1, -- mysql query error
REDIS = 2, -- redis command error
HTTP = 3, -- http request error
INVALID_EVENT = 11, -- event not defined

LOCK = 1001, -- mysql optimistic lock
WATCH = 1002, -- redis transaction error

SIGNIN_ALREADY = 2001, -- already signed in
SIGNIN_UNAUTH = 2002, -- sid unauthorized
</pre>
