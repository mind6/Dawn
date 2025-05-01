"""
NOTE: In this case it seems from mouse click to rendering, we could have passed around indices into some trades table. But it would have quickly exploded the amount of "stuff to keep in mind". As a general principle, make argument data as independent of other datastructures as possible, even if it seems to create repetitive lookup in some cases. The older Julia packages would be much easier to use if this principle was followed. I suppose this is a kind decoupling behind JSON and REST api's, "just the facts, data format!"

when 'nothing' is passed, the first available provider or trade is selected. this can be helpful in testing.
"""
function selecttrade(provname::Union{Nothing, Symbol}=nothing, timeoftrade::Union{Nothing, DateTime}=nothing)::Union{Nothing, Tuple{Symbol, DateTime}}
   if isempty(traderuns) || selected_idx == 0 || isempty(traderuns[selected_idx].trprov_ctrls)
      error("must create or select a trade run")
   end

   global curtradectrl = provname === nothing ? 
      traderuns[selected_idx].trprov_ctrls[1] : Dawn.get_tradeprovctrl_by_providername(provname)
   if isempty(curtradectrl.trades)
      error("no trades were found for $(curtradectrl.providername). Have you called executetraderun()?")
   end

   global curtradeidx = timeoftrade === nothing ?
      1 : MyData.getloc(curtradectrl.trades, timeoftrade)
   global curdate = curtradectrl.trades[curtradeidx, :dateordinal]

   currenttradeid()
end

"Return true if successful, false if no current trade is selected."
function nexttrade()::Bool
   return _movetrade(1)
end

"Return true if successful, false if no current trade is selected."
function prevtrade()::Bool
   return _movetrade(-1)
end

function _movetrade(offset::Int)::Bool
   if curtradectrl === nothing || isempty(curtradectrl.trades)
      return false 
   end

   global curtradeidx = MyMath.modind(curtradeidx + offset, nrow(curtradectrl.trades))
   global curdate = curtradectrl.trades[curtradeidx,:dateordinal]

   return true
end

"Return true if successful, false if no current date is selected."
function nextday()::Bool
   if curtradectrl === nothing || curdate === nothing 
      return false
   end
   bm1 = curtradectrl.combineddata
   ind = searchsortedlast(bm1.dateordinal, curdate)
   ind = MyMath.modind(ind + 1, nrow(bm1))
   global curdate = bm1.dateordinal[ind]
   selectfirsttradeofday()
   return true
end

"Return true if successful, false if no current date is selected."
function prevday()::Bool
   if curtradectrl === nothing || curdate === nothing 
      return false
   end
   bm1 = curtradectrl.combineddata
   ind = searchsortedfirst(bm1.dateordinal, curdate)
   ind = MyMath.modind(ind - 1, nrow(bm1))
   global curdate = bm1.dateordinal[ind]
   selectfirsttradeofday()
   return true
end

function selectfirsttradeofday()::Bool
   if curtradectrl === nothing || isempty(curtradectrl.trades) || curdate === nothing
      return false
   end

   dft = curtradectrl.trades
   ind = searchsortedfirst(dft.dateordinal, curdate)
   if ind ∈ 1:nrow(dft) && dft.dateordinal[ind] == curdate
      global curtradeidx = ind
      return true
   else
      return false
   end
end
