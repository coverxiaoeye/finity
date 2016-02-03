local M = {}

--字符串转lua对象
M.dec = function(s)
  return loadstring('return ' .. s)()
end

--lua table转字符串
M.enc = function(t)
  local tos
  local function vs(v)
    if 'string' == type(v) then
      v = string.gsub(v, '\n', '\\n')
      return '\'' .. string.gsub(v, '\'', '\\\'') .. '\''
    else
      return 'table' == type(v) and tos(v) or tostring(v)
    end
  end
  local function ks(k)
    if 'string' == type(k) and string.match(k, '^[_%a][_%a%d]*$') then
      return k
    else
      return '[' .. vs(k) .. ']'
    end
  end
  tos = function(t)
    local s, done = {}, {}
    for k, v in ipairs(t) do
      s[#s + 1] = vs(v)
      done[k] = true
    end
    for k, v in pairs(t) do
      if not done[k] then
        s[#s + 1] = ks(k) .. '=' .. vs(v)
      end
    end
    return '{' .. table.concat(s, ',') .. '}'
  end
  return tos(t)
end

return M

