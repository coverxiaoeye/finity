# Description
A websocket game server template using OpenResty/Redis/Mysql.

## Request format(json object)
<pre>
{
  "id": #type: number, description: client specified id which will be returned on publishing.
  "event": #type: string, description: event name, such as 'signin', 'ping', etc.
  "args": #type: any, description: arguments of this event.
}
</pre>

## Response format(json object)
<pre>
{
  "id": #type: number, description: client specified id or <b>0</b> when this notification dispatched by server side.
  "event": #type: string, description: event name, such as 'signin', 'ping', etc.
  "args": #type: any, description: arguments of this event, <b>NULLABLE</b>.
  "err": "type: number, description: error code, <b>NULLABLE</b>.
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