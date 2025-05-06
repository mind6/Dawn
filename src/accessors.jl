#=
Read-only accessors for Dawn state.
=#
function get_tradeprovctrls()::AbstractVector{TradeProviderControl}
	if selected_idx ∉ 1:length(traderuns)
		@error "no valid TradeRun selected at $selected_idx"
		return
	end

	traderuns[selected_idx].trprov_ctrls
end

function get_tradeprovctrl_by_providername(providername::Symbol)::TradeProviderControl
	truncontext = currenttraderun()
	if !haskey(truncontext.provname2provctrl, providername)
		error("trade control for $providername not found. Have you called `summarizetrades()`?")
	end
	truncontext.provname2provctrl[providername]
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


function selectedidx() selected_idx end

function currenttraderun() traderuns[selected_idx] end

"Returns providername and timeoftrade "
function currenttrade()::Union{Nothing, DataFrameRow}
	truncontext = currenttraderun()
	if truncontext.curtradectrl !== nothing && truncontext.summary !== nothing
		if !haskey(truncontext.summary.provname2summary, truncontext.curtradectrl.providername)
			return nothing
		end
		provsummary = truncontext.summary.provname2summary[truncontext.curtradectrl.providername]
		if !isempty(provsummary.trades) && truncontext.curtradeidx in 1:nrow(provsummary.trades)
			provsummary.trades[truncontext.curtradeidx,:]
		else
			nothing
		end
	else
		nothing
	end
end

function currentprovider()::Union{Nothing, Symbol}
	truncontext = currenttraderun()
	if truncontext.curtradectrl !== nothing
		truncontext.curtradectrl.providername
	else
		nothing
	end
end

function currenttradeid()::Union{Nothing, Tuple{Symbol, DateTime}}
	truncontext = currenttraderun()
	if truncontext.curtradectrl === nothing || truncontext.summary === nothing
		return nothing
	end
	if !haskey(truncontext.summary.provname2summary, truncontext.curtradectrl.providername)
		return nothing
	end
	provsummary = truncontext.summary.provname2summary[truncontext.curtradectrl.providername]
	if isempty(provsummary.trades) || truncontext.curtradeidx ∉ 1:nrow(provsummary.trades)
		return nothing
	end
	return (truncontext.curtradectrl.providername, provsummary.trades[truncontext.curtradeidx,:datetime])		
end

function currentdateid()::Union{Nothing, Tuple{Symbol, UnixDate}}
	truncontext = currenttraderun()
	if truncontext.curtradectrl === nothing || truncontext.curdate === nothing
		return nothing
	end
	return (truncontext.curtradectrl.providername, truncontext.curdate)		
end

function get_tradesummary_row()
	truncontext = currenttraderun()
	if truncontext.curtradectrl === nothing || truncontext.summary === nothing
		error("No current trade selected or summary available")
	end
	if !haskey(truncontext.summary.provname2summary, truncontext.curtradectrl.providername)
		error("No summary found for current provider")
	end
	provsummary = truncontext.summary.provname2summary[truncontext.curtradectrl.providername]
	get_tradesummary_row(truncontext.curtradectrl.providername, provsummary.trades[truncontext.curtradeidx,:datetime])
end

function get_tradesummary_row(provider::Symbol, datetime::DateTime)
	truncontext = currenttraderun()
	if truncontext.summary === nothing
		error("No trade summary available. Have you called summarizetrades()?")
	end
	subdf = truncontext.summary.tradesummary_gb[(provider, )]
	subdf[MyData.getloc(subdf.datetime, datetime), :]
end

function get_bm1_row(provname::Symbol, datetime::DateTime)
	truncontext = currenttraderun()
	if truncontext.summary === nothing
		error("No trade summary available. Have you called summarizetrades()?")
	end
	if !haskey(truncontext.summary.provname2summary, provname)
		error("No summary found for provider $provname")
	end
	provsummary = truncontext.summary.provname2summary[provname]
	df = provsummary.combineddata
	df[MyData.getloc(df, datetime), :]
end

"Returns the daily bars data frame 'bday' and 'daypos' corresponding to currentdateid(). The result can be directly spliced into MyPlots.render_bday(...)"
function get_current_bday()::Union{Nothing, Tuple{AbstractDataFrame, Int}}
	truncontext = currenttraderun()
	#tid = (pathname, curdate)
	tid::Union{Nothing, Tuple{Symbol, UnixDate}} = currentdateid() 
	if tid === nothing return nothing end

	symbol = split(String(tid[1]), '!')[2]
	if truncontext.curbday === nothing || metadata(truncontext.curbday, "symbol") != symbol #invalidate curbday, populate it with bday from AssetData
		truncontext.curbday = MyData.AssetData(symbol).bday
	end

	loc = searchsortedlast(truncontext.curbday.dateordinal, tid[2])
	return (truncontext.curbday, loc)
end

"Get current day's plus previous available trading day's minute bars from 'provider_ctrl.combineddata' corresponding to the given 'provname'. All provider supplies stats will be included."
function get_twodays_bm1()::AbstractDataFrame
	truncontext = currenttraderun()
	if truncontext.curdate === nothing || truncontext.summary === nothing || truncontext.curtradectrl === nothing
		return DataFrame()
	end

	if !haskey(truncontext.summary.provname2summary, truncontext.curtradectrl.providername)
		error("No summary found for current provider")
	end
	provsummary = truncontext.summary.provname2summary[truncontext.curtradectrl.providername]
	bm1 = provsummary.combineddata
	
	bm1start=searchsortedfirst(bm1.dateordinal, truncontext.curdate)
	bm1end=searchsortedlast(bm1.dateordinal, truncontext.curdate)  
	if bm1start != 1 
		bm1start=searchsortedfirst(bm1.dateordinal, bm1.dateordinal[bm1start-1])
	end 
	@view bm1[bm1start:bm1end, :]
end
