local throw = require('throw')
local config = require('config')

return function(db)
  local M = { db = db }

  function M.queryone(sql, ...)
    local s = string.format(sql, ...)
    if config.debug then
      ngx.log(ngx.DEBUG, s)
    end

    local ret, err, errno, sqlstate = M.db:query(s, 1)
    if not ret then
      ngx.log(ngx.ERR, 'failed to queryone: ', err)
      throw(1)
    end
    return ret[1]
  end

  function M.query(sql, ...)
    local s = string.format(sql, ...)
    if config.debug then
      ngx.log(ngx.DEBUG, s)
    end

    local ret, err, errno, sqlstate = M.db:query(s)
    if not ret then
      ngx.log(ngx.ERR, 'failed to query: ', err)
      throw(1)
    end
    return ret
  end

  function M.update(sql, ...)
    local s = string.format(sql, ...)
    if config.debug then
      ngx.log(ngx.DEBUG, s)
    end

    local ret, err, errno, sqlstate = M.db:query(s)
    if not ret then
      ngx.log(ngx.ERR, 'failed to update: ', err)
      throw(1)
    end
    return ret.affected_rows
  end

  function M.insert(sql, ...)
    local s = string.format(sql, ...)
    if config.debug then
      ngx.log(ngx.DEBUG, s)
    end

    local ret, err, errno, sqlstate = M.db:query(s)
    if not ret then
      ngx.log(ngx.ERR, 'failed to insert: ', err)
      throw(1)
    end
    return ret.insert_id
  end

  function M.updates(sql, ps, each)
    if config.debug then
      ngx.log(ngx.DEBUG, sql)
      ngx.log(ngx.DEBUG, util.tostring(ps))
    end

    local ret, err, errno, sqlstate = M.db:query("PREPARE data_updates FROM '" .. sql .. "'")
    if not ret then
      ngx.log(ngx.ERR, 'failed to mysql prepare: ', err)
      throw(1)
    end
    for _, v in ipairs(ps) do
      local us = {}
      for i, vv in ipairs(v) do
        ret, err, errno, sqlstate = M.db:query('SET @p' .. i .. ' = ' .. vv)
        if not ret then
          ngx.log(ngx.ERR, 'failed to mysql set: ', err)
          throw(1)
        end
        table.insert(us, '@p' .. i)
      end
      ret, err, errno, sqlstate = M.db:query('EXECUTE data_updates USING ' .. table.concat(us, ','))
      if not ret then
        ngx.log(ngx.ERR, 'failed to mysql execute: ', err)
        throw(1)
      end
      if each and ret.affected_rows < 1 then
        ngx.log(ngx.ERR, 'mysql affected_rows less than 1')
        throw(1)
      end
    end
    ret, err, errno, sqlstate = M.db:query('DEALLOCATE PREPARE data_updates')
    if not ret then
      ngx.log(ngx.ERR, 'failed to mysql deallocate prepare: ', err)
      throw(1)
    end
  end

  function M.inserts(sql, ps)
    if config.debug then
      ngx.log(ngx.DEBUG, sql)
      ngx.log(ngx.DEBUG, util.tostring(ps))
    end

    local ids = {}
    local ret, err, errno, sqlstate = M.db:query("PREPARE data_inserts FROM '" .. sql .. "'")
    if not ret then
      ngx.log(ngx.ERR, 'failed to mysql prepare: ', err)
      throw(1)
    end
    for _, v in ipairs(ps) do
      local us = {}
      for i, vv in ipairs(v) do
        ret, err, errno, sqlstate = M.db:query('SET @p' .. i .. ' = ' .. vv)
        if not ret then
          ngx.log(ngx.ERR, 'failed to mysql set: ', err)
          throw(1)
        end
        table.insert(us, '@p' .. i)
      end
      ret, err, errno, sqlstate = M.db:query('EXECUTE data_inserts USING ' .. table.concat(us, ','))
      if not ret then
        ngx.log(ngx.ERR, 'failed to mysql execute: ', err)
        throw(1)
      end
      table.insert(ids, ret.insert_id)
    end
    ret, err, errno, sqlstate = M.db:query('DEALLOCATE PREPARE data_inserts')
    if not ret then
      ngx.log(ngx.ERR, 'failed to mysql deallocate prepare: ', err)
      throw(1)
    end
    return ids
  end

  return M
end
