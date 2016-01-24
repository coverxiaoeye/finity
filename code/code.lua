return
{
  UNKNOWN = -1, -- unknown error (bugs, json decoding, etc.)
  MYSQL = 1, -- mysql query error
  REDIS = 2, -- redis command error
  HTTP = 3, -- http request error
  INVALID_EVENT = 11, -- event not defined

  LOCK = 1001, -- mysql optimistic lock
  WATCH = 1002, -- redis transaction error

  SIGNIN_ALREADY = 2001, -- already signed in
  SIGNIN_UNAUTH = 2002, -- sid unauthorized
}
