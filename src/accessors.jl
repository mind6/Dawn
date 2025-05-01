#=
Read-only accessors for Dawn state.
=#
function get_tradeprovctrls()::AbstractVector{TradeProviderControl}
   if tradecontext.selected_idx ∉ 1:length(tradecontext.traderuns)
      @error "no valid TradeRun selected at $(tradecontext.selected_idx)"
      return
   end

   tradecontext.traderuns[tradecontext.selected_idx].trprov_ctrls
end

function get_tradeprovctrl_by_providername(providername::Symbol)::TradeProviderControl
   if !haskey(tradecontext.provname2provctrl, providername)
      error("trade control for $providername not found. Have you called `summarizetrades()`?")
   end
   tradecontext.provname2provctrl[providername]
end

function get_reference_columnnames(refchartsinks::sp.RefChartSink...)::Vector{Symbol}
   cols = Symbol[]
   for refsink in refchartsinks
      for aut in Dawn.sp.get_referencenAUTs(refsink)
         for field in refsink.ref_fields
            colname = Dawn.sp.get_refdata_columnname(refsink, aut, field)
            push!(cols, colname)
         end
      end
   end
   cols
end


function selectedidx() tradecontext.selected_idx end

function currenttraderun() tradecontext.traderuns[tradecontext.selected_idx] end

"Returns providername and timeoftrade "
function currenttrade()::Union{Nothing, DataFrameRow}
   if tradecontext.curtradectrl !== nothing
      tradecontext.curtradectrl.trades[tradecontext.curtradeidx,:]
   else
      nothing
   end
end

function currentprovider()::Union{Nothing, Symbol}
   if tradecontext.curtradectrl !== nothing
      tradecontext.curtradectrl.providername
   else
      nothing
   end
end

function currenttradeid()::Union{Nothing, Tuple{Symbol, DateTime}}
   if tradecontext.curtradectrl === nothing || isempty(tradecontext.curtradectrl.trades)
      return nothing
   end
   return (tradecontext.curtradectrl.providername, tradecontext.curtradectrl.trades[tradecontext.curtradeidx,:datetime])      
end

function currentdateid()::Union{Nothing, Tuple{Symbol, UnixDate}}
   if tradecontext.curtradectrl === nothing || tradecontext.curdate === nothing
      return nothing
   end
   return (tradecontext.curtradectrl.providername, tradecontext.curdate)      
end

function get_tradesummary_row()
   get_tradesummary_row(tradecontext.curtradectrl.providername, tradecontext.curtradectrl.trades[tradecontext.curtradeidx,:datetime])
end

function get_tradesummary_row(provider::Symbol, datetime::DateTime)
   subdf = tradecontext.tradesummary_gb[(provider, )]
   subdf[MyData.getloc(subdf.datetime, datetime), :]
end

function get_bm1_row(provname::Symbol, datetime::DateTime)
   df = tradecontext.provname2provctrl[provname].combineddata
   df[MyData.getloc(df, datetime), :]
end

"Returns the daily bars data frame 'bday' and 'daypos' corresponding to currentdateid(). The result can be directly spliced into MyPlots.render_bday(...)"
function get_current_bday()::Union{Nothing, Tuple{AbstractDataFrame, Int}}
   #tid = (pathname, curdate)
   tid::Union{Nothing, Tuple{Symbol, UnixDate}} = currentdateid() 
   if tid === nothing return nothing end

   symbol = split(String(tid[1]), '!')[2]
   if tradecontext.curbday === nothing || metadata(tradecontext.curbday, "symbol") != symbol #invalidate curbday, populate it with bday from AssetData
      tradecontext.curbday = MyData.AssetData(symbol).bday
   end

   loc = searchsortedlast(tradecontext.curbday.dateordinal, tid[2])
   return (tradecontext.curbday, loc)
end

"Get current day's plus previous available trading day's minute bars from 'provider_ctrl.combineddata' corresponding to the given 'provname'. All provider supplies stats will be included."
function get_twodays_bm1()::AbstractDataFrame
   if tradecontext.curdate === nothing return DataFrame() end

   # dateord = curtradectrl.trades[curtradeidx,:dateordinal]
   # dateord = curtradectrl.trades[curtradeidx,:dateordinal]
   bm1 = tradecontext.curtradectrl.combineddata
   bm1start=searchsortedfirst(bm1.dateordinal, tradecontext.curdate)
   bm1end=searchsortedlast(bm1.dateordinal, tradecontext.curdate)  
   if bm1start != 1 
      bm1start=searchsortedfirst(bm1.dateordinal, bm1.dateordinal[bm1start-1])
   end 
   @view bm1[bm1start:bm1end, :]
end
