return
{
  KEY_SESSION = 'session', -- session connected SET
  KEY_PLAYER = 'player', -- player/{playerid} -> {group: xxx}
  KEY_GROUP = 'group', -- group/{groupid} -> {state: wait/begin/quit, member: "{xxx,yyy,...}"}
  KEY_GROUP_N = 'groupn', -- current group id, for INCR
  KEY_HERO = 'hero', -- hero/{groupid} -> hero id LIST sent
}