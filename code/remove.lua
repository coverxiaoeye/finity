--从表中删除最后一个内容相等的元素
return function(t, e)
  for i = #t, 1, -1 do
    if t[i] == e then
      table.remove(t, i)
      break
    end
  end
end
