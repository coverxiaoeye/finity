return
{
  UNKNOWN = -1, -- unknown error (bugs, json decoding, etc.)
  MYSQL = 1, -- mysql query error
  REDIS = 2, -- redis command error
  HTTP = 3, -- http request error

  INVALID_EVENT = 11, -- event not defined

  SIGNIN_ALREADY = 1001, -- already signed in
  SIGNIN_UNAUTH = 1002, -- sid unauthorized
}
