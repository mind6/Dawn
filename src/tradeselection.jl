#=
Functions for selecting trades and navigating through time (trade data).
=#

# Start navigation
function selecttrade(timeoftrade::DateTime; provname::Union{Nothing, Symbol}=nothing)
   if isempty(traderuns) || selected_idx == 0 || isempty(traderuns[selected_idx].trprov_ctrls)
      @error "no valid TradeRun exists."
      return
   end
   truncontext = currenttraderun()
   truncontext.curtradectrl = provname === nothing ? 
      truncontext.trprov_ctrls[1] : get_tradeprovctrl_by_providername(provname)
   if isempty(truncontext.curtradectrl.trades)
      error("no trades were found for $(truncontext.curtradectrl.providername). Have you called executetraderun()?")
   end

   truncontext.curtradeidx = timeoftrade === nothing ?
      1 : MyData.getloc(truncontext.curtradectrl.trades, timeoftrade)
   truncontext.curdate = truncontext.curtradectrl.trades[truncontext.curtradeidx, :dateordinal]
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

   truncontext = currenttraderun()
   if truncontext.curtradectrl === nothing || isempty(truncontext.curtradectrl.trades)
      @error "no trades selected"
      return
   end
   truncontext.curtradeidx = MyMath.modind(truncontext.curtradeidx + offset, nrow(truncontext.curtradectrl.trades))
   truncontext.curdate = truncontext.curtradectrl.trades[truncontext.curtradeidx,:dateordinal]
   @info "selected trade: $(currenttradeid())"
   @info "selected date: $(currentdateid())"
end


function _prevday()
   truncontext = currenttraderun()
   if truncontext.curtradectrl === nothing || truncontext.curdate === nothing 
      @warn "previous day navigation requires call to initselections() first"
   end
   bm1 = truncontext.curtradectrl.combineddata
   ind = searchsortedlast(bm1.dateordinal, truncontext.curdate)
   ind -= 1
   truncontext.curdate = bm1.dateordinal[ind]
   @info "selected date: $(currentdateid())"
end

function _nextday()
   truncontext = currenttraderun()
   if truncontext.curtradectrl === nothing || truncontext.curdate === nothing 
      @warn "next day navigation requires call to initselections() first"
   end
   bm1 = truncontext.curtradectrl.combineddata
   ind = searchsortedfirst(bm1.dateordinal, truncontext.curdate)
   ind += 1
   truncontext.curdate = bm1.dateordinal[ind]
   @info "selected date: $(currentdateid())"
end

"Update curtradeidx if there is a trade on the newly selected day."
function _synctrade2date()
   truncontext = currenttraderun()
   if truncontext.curtradectrl === nothing || isempty(truncontext.curtradectrl.trades) || truncontext.curdate === nothing
      @warn "sync navigation requires call to initselections() first"
   end

   dft = truncontext.curtradectrl.trades
   ind = searchsortedfirst(dft.dateordinal, truncontext.curdate)
   if ind ∈ 1:nrow(dft) && dft.dateordinal[ind] == truncontext.curdate
      truncontext.curtradeidx = ind
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
