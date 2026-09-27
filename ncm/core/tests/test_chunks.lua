return {
  twenty_five_market_rows_round_trip_in_bounded_packets=function(T)
    local C=T.Core.get("vocabulary.chunks")
    local rows={} for i=1,25 do rows[i]={designId="part-"..i} end
    local packets=C.partition(rows,1)
    T.eq(#packets,25)
    for _,p in ipairs(packets) do T.eq(#p,1,"a component packet must contain one complete offering") end
    local rx=C.receiver(#packets)
    for i=#packets,1,-1 do T.truthy(C.accept(rx,i,packets[i])) end
    T.truthy(C.complete(rx))
    local rebuilt=C.collect(rx)
    T.eq(#rebuilt,25);T.eq(rebuilt[1].designId,"part-1");T.eq(rebuilt[25].designId,"part-25")
  end,
  missing_duplicate_and_foreign_parts_do_not_complete=function(T)
    local C=T.Core.get("vocabulary.chunks");local rx=C.receiver(2)
    T.falsy(C.accept(rx,3,{{}}));T.truthy(C.accept(rx,1,{{id=1}}));T.falsy(C.accept(rx,1,{{id=9}}))
    T.falsy(C.complete(rx));T.falsy(C.collect(rx));T.truthy(C.accept(rx,2,{{id=2}}));T.truthy(C.complete(rx))
  end,
}
