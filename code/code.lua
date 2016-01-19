return
{
  UNKNOWN = -1, -- unknown error (bugs, json decoding, etc.)
  MYSQL = 1, -- mysql query error
  REDIS = 2, -- redis command error

  INVALID_EVENT = 11, --event not defined
}

