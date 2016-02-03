local M =
{
  KEY_SESSION = 'session', -- session connected SET
  KEY_PLAYER = 'player', -- player/{playerid} -> {group: xxx}
  KEY_GROUP = 'group', -- group/{groupid} -> {state: wait/begin/quit, member: "{xxx,yyy,...}"}
  KEY_GROUP_N = 'groupn', -- current group id, for INCR
  KEY_HERO = 'hero', -- hero/{groupid} -> hero id LIST sent
}

M.session = function()
  return M.KEY_SESSION
end

M.player = function(id)
  return M.KEY_PLAYER .. '/' .. id
end

M.group = function(id)
  return M.KEY_GROUP .. '/' .. id
end

M.groupn = function()
  return M.KEY_GROUP_N
end

M.hero = function(id)
  return M.KEY_HERO .. '/' .. id
end

return M