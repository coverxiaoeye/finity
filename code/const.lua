local M =
{
  KEY_SESSION = 'session',
  KEY_PLAYER = 'player',
  KEY_GROUP = 'group',
  KEY_GROUP_N = 'groupn',
  KEY_HERO = 'hero',
}

--全服会话列表 SET
M.session = function()
  return M.KEY_SESSION
end

--玩家信息 HSET {group: xxx}
M.player = function(id)
  return M.KEY_PLAYER .. '/' .. id
end

--游戏组信息 HSET {state: wait/begin/quit, member: "{playerid,...}"}
M.group = function(id)
  return M.KEY_GROUP .. '/' .. id
end

--当前最大组号 INCR
M.groupn = function()
  return M.KEY_GROUP_N
end

--某个游戏组内英雄信息 LIST
M.hero = function(id)
  return M.KEY_HERO .. '/' .. id
end

return M