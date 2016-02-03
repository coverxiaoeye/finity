return function(t, e)
  for i = #t, 1, -1 do
    if t[i] == e then
      table.remove(t, i)
      break
    end
  end
end
