#=
Functions for selecting trades and navigating through time (trade data).
=#

# Start navigation
function selecttrade(timeoftrade::DateTime; provname::Union{Nothing, Symbol}=nothing)
   if isempty(tradecontext.traderuns) || tradecontext.selected_idx == 0 || isempty(tradecontext.traderuns[tradecontext.selected_idx].trprov_ctrls)
      @error "no valid TradeRun exists."
      return
   end
   tradecontext.curtradectrl = provname === nothing ? 
      tradecontext.traderuns[tradecontext.selected_idx].trprov_ctrls[1] : Dawn.get_tradeprovctrl_by_providername(provname)
   if isempty(tradecontext.curtradectrl.trades)
      error("no trades were found for $(tradecontext.curtradectrl.providername). Have you called executetraderun()?")
   end

   tradecontext.curtradeidx = timeoftrade === nothing ?
      1 : MyData.getloc(tradecontext.curtradectrl.trades, timeoftrade)
   tradecontext.curdate = tradecontext.curtradectrl.trades[tradecontext.curtradeidx, :dateordinal]
   @info "selected trade: $(currenttradeid())"
   @info "selected date: $(currentdateid())"
end

# Navigation
function selecttrade(provname::Symbol)
   selecttrade(nothing, provname=provname)
end

"Skip to the prev or next trade within curtradectrl, cyclic mode. Skip within same provider"
function _nextrade(offset::Int)
   offset ∈ [-1, 1] || error("offset must be -1 or 1")

   if tradecontext.curtradectrl === nothing || isempty(tradecontext.curtradectrl.trades)
      @error "no trades selected"
      return
   end
   tradecontext.curtradeidx = MyMath.modind(tradecontext.curtradeidx + offset, nrow(tradecontext.curtradectrl.trades))
   tradecontext.curdate = tradecontext.curtradectrl.trades[tradecontext.curtradeidx,:dateordinal]
   @info "selected trade: $(currenttradeid())"
   @info "selected date: $(currentdateid())"
end


function _prevday()
   if tradecontext.curtradectrl === nothing || tradecontext.curdate === nothing 
      @warn "previous day navigation requires call to initselections() first"
   end
   bm1 = tradecontext.curtradectrl.combineddata
   ind = searchsortedlast(bm1.dateordinal, tradecontext.curdate)
   ind -= 1
   tradecontext.curdate = bm1.dateordinal[ind]
   @info "selected date: $(currentdateid())"
end

function _nextday()
   if tradecontext.curtradectrl === nothing || tradecontext.curdate === nothing 
      @warn "next day navigation requires call to initselections() first"
   end
   bm1 = tradecontext.curtradectrl.combineddata
   ind = searchsortedfirst(bm1.dateordinal, tradecontext.curdate)
   ind += 1
   tradecontext.curdate = bm1.dateordinal[ind]
   @info "selected date: $(currentdateid())"
end

"Update curtradeidx if there is a trade on the newly selected day."
function _synctrade2date()
   if tradecontext.curtradectrl === nothing || isempty(tradecontext.curtradectrl.trades) || tradecontext.curdate === nothing
      @warn "sync navigation requires call to initselections() first"
   end

   dft = tradecontext.curtradectrl.trades
   ind = searchsortedfirst(dft.dateordinal, tradecontext.curdate)
   if ind ∈ 1:nrow(dft) && dft.dateordinal[ind] == tradecontext.curdate
      tradecontext.curtradeidx = ind
      @info "synced to trade: $(currenttradeid())"      
   end
end

function nexttrade()
   _nextrade(1)
end
function prevtrade()
   _nextrade(-1)
end

function nextday()
   _nextday() 
   _synctrade2date()
end
function prevday()
   _prevday()
   _synctrade2date()
end
