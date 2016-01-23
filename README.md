# Description
A websocket game server template running on
<a href="http://openresty.org" target="_blank">OpenResty</a>
<a href="http://redis.io" target="_blank">Redis</a>
Mysql

## Request json format
<pre>
{
  "id": #type: number #description: client specified event id which will be returned unchanged.
  "event": #type: string #description: event name, such as 'signin', 'ping', etc.
  "args": #type: any #description: arguments of this event.
}
</pre>

## Response json format
<pre>
{
  "id": #type: number #description: client specified event id or <b>0</b> on broadcasting.
  "event": #type: string #description: event name, such as 'signin', 'ping', etc.
  "args": #type: any #description: arguments of this event, <b>NULLABLE</b>.
  "err": "type: number #description: error code, <b>NULLABLE</b>.
}
</pre>

## Error code
<pre>
UNKNOWN = -1, -- unknown error (bugs, json decoding, etc.)
MYSQL = 1, -- mysql query error
REDIS = 2, -- redis command error
HTTP = 3, -- http request error

INVALID_EVENT = 11, -- event not defined

SIGNIN_ALREADY = 1001, -- already signed in
SIGNIN_UNAUTH = 1002, -- sid unauthorized
</pre>

## Event list

[ping](#ping)&nbsp;&nbsp;&nbsp;[signin](#signin)

### ping
Ping event to keep the current connection.
This event should be sent only if sign in completed.

FORMAT: {"id": xxx, "event": "ping", "args": xxx}
* <b>args</b> can be omitted (better)

### signin
Sign in should be the first event sent to server.
Connection will be closed on any errors.
Idle connections will be closed within 9 seconds.

FORMAT: {"id": xxx, "event": "signin", "args": {"sid": "xxx"}}
* <b>sid</b> is a string obtained from gate server

### TODO: OTHER EVENTS