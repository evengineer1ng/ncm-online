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
  -- KB-160. The Race Guide broke twice at the SAME seventeen rows, because the rows grew. A row-count budget
  -- cannot see that; a byte budget can.
  byte_budget_packs_by_measured_size_not_row_count=function(T)
    local C=T.Core.get("vocabulary.chunks")
    local rows={} for i=1,17 do rows[i]={n=i} end
    local packets,oversized=C.partitionBytes(rows,6*1024,function() return 1300 end)
    T.eq(#oversized,0)
    for _,pk in ipairs(packets) do T.truthy(#pk*1300<=6*1024,"every packet stays inside the byte budget") end
    local rx=C.receiver(#packets)
    for i=1,#packets do T.truthy(C.accept(rx,i,packets[i])) end
    local rebuilt=C.collect(rx)
    T.eq(#rebuilt,17);T.eq(rebuilt[1].n,1);T.eq(rebuilt[17].n,17)
    -- the same seventeen rows after growth: more packets, never a dropped payload
    local fatter=C.partitionBytes(rows,6*1024,function() return 2600 end)
    T.truthy(#fatter>#packets,"a row that grows must cost a packet, not the payload")
  end,
  a_row_larger_than_the_budget_is_reported_and_sent_alone=function(T)
    local C=T.Core.get("vocabulary.chunks")
    local rows={{n=1},{n=2},{n=3}}
    local packets,oversized=C.partitionBytes(rows,1000,function(r) return r.n==2 and 4000 or 100 end)
    T.eq(#oversized,1);T.eq(oversized[1].index,2);T.eq(oversized[1].bytes,4000)
    T.eq(#packets,3,"the oversized row is isolated so the rest still arrive")
    T.eq(#packets[2],1);T.eq(packets[2][1].n,2)
    -- everything still round-trips: an oversized row is reported, never dropped
    local rx=C.receiver(#packets)
    for i=1,#packets do T.truthy(C.accept(rx,i,packets[i])) end
    T.eq(#C.collect(rx),3)
  end,
  an_unmeasurable_row_is_assumed_to_fill_the_budget=function(T)
    local C=T.Core.get("vocabulary.chunks")
    local rows={{n=1},{n=2}}
    -- -1 is what the server's encoder returns for a value it cannot encode. Trusting it as "1 byte" would put
    -- the unknown quantity in a packet with everything else, which is the failure mode this exists to prevent.
    local packets=C.partitionBytes(rows,1000,function() return -1 end)
    T.eq(#packets,2)
  end,
  missing_duplicate_and_foreign_parts_do_not_complete=function(T)
    local C=T.Core.get("vocabulary.chunks");local rx=C.receiver(2)
    T.falsy(C.accept(rx,3,{{}}));T.truthy(C.accept(rx,1,{{id=1}}));T.falsy(C.accept(rx,1,{{id=9}}))
    T.falsy(C.complete(rx));T.falsy(C.collect(rx));T.truthy(C.accept(rx,2,{{id=2}}));T.truthy(C.complete(rx))
  end,
}
