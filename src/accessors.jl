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


"""
Get current trade from summary.
"""
function getcurrenttrade(summary::TradeRunSummary)
	if summary.curtradeprov_name === nothing || summary.curtradeidx == 0
		return nothing
	end
	
	provsummary = getcurrentprovsummary(summary)
	provsummary.trades[summary.curtradeidx, :]
end

"""
Get current provider from summary.
"""
function getcurrentprovider(summary::TradeRunSummary)
	summary.curtradeprov_name
end

function getcurrentprovsummary(summary::TradeRunSummary)
	if summary.curtradeprov_name === nothing
		return nothing
	end
	summary.provname2summary[summary.curtradeprov_name]
end


"""
Get current trade id from summary.
"""
function getcurrenttradeid(summary::TradeRunSummary)
	if summary.curtradeprov_name === nothing || summary.curtradeidx == 0
		return nothing
	end
	
	provsummary = getcurrentprovsummary(summary)
	(summary.curtradeprov_name, provsummary.trades[summary.curtradeidx, :datetime])
end

"""
Get current date id from summary.
"""
function getcurrentdateid(summary::TradeRunSummary)
	if summary.curtradeprov_name === nothing || summary.curdate === nothing
		return nothing
	end
	
	(summary.curtradeprov_name, summary.curdate)
end

"""
Get current day's minute bars from summary.
"""
function get_current_bm1(summary::TradeRunSummary)
	if summary.curtradeprov_name === nothing || summary.curdate === nothing
		return DataFrame()
	end
	
	provsummary = getcurrentprovsummary(summary)
	bm1 = provsummary.combineddata
	
	bm1start = searchsortedfirst(bm1.dateordinal, summary.curdate)
	bm1end = searchsortedlast(bm1.dateordinal, summary.curdate)
	
	@view bm1[bm1start:bm1end, :]
end

"""
Get two days of minute bars from summary.
"""
function get_twodays_bm1(summary::TradeRunSummary)
	if summary.curtradeprov_name === nothing || summary.curdate === nothing
		return DataFrame()
	end
	
	provsummary = getcurrentprovsummary(summary)
	bm1 = provsummary.combineddata
	
	bm1start = searchsortedfirst(bm1.dateordinal, summary.curdate)
	bm1end = searchsortedlast(bm1.dateordinal, summary.curdate)
	if bm1start != 1
		bm1start = searchsortedfirst(bm1.dateordinal, bm1.dateordinal[bm1start-1])
	end
	
	@view bm1[bm1start:bm1end, :]
end

"""
Get current daily bar data from summary.
"""
function get_current_bday(summary::TradeRunSummary)
	dateid = getcurrentdateid(summary)
	if dateid === nothing
		return nothing
	end
	
	providername, curdate = dateid
	symbol = split(String(providername), '!')[2]
	
	# Cache invalidation
	if summary.curbday === nothing || metadata(summary.curbday, "symbol") != symbol
		summary.curbday = MyData.AssetData(symbol).bday
	end
	
	loc = searchsortedlast(summary.curbday.dateordinal, curdate)
	return (summary.curbday, loc)
end

"""
Get current trade summary row.
"""
function get_current_tradesummary_row(summary::TradeRunSummary)
	tradeid = getcurrenttradeid(summary)
	if tradeid === nothing
		error("No current trade selected")
	end
	
	provider, datetime = tradeid
	get_tradesummary_row(summary, provider, datetime)
end

"""
Get trade summary row from the grouped dataframe.
"""
function get_tradesummary_row(summary::TradeRunSummary, provider::Symbol, datetime::DateTime)
	subdf = summary.tradesummary_byprov[(provider, )]
	subdf[MyData.getloc(subdf.datetime, datetime), :]
end


"""
Get a row from combined data by datetime.
"""
function get_bm1_row(summary::TradeRunSummary, provname::Symbol, datetime::DateTime)
	provsummary = getcurrentprovsummary(summary)
	if provsummary === nothing
		return DataFrame()
	end
	df = provsummary.combineddata
	df[MyData.getloc(df, datetime), :]
end

"""
Get a range of minute bars from combined data.
"""
function get_bm1_rows(summary::TradeRunSummary, provname::Symbol, date::UnixDate)
	provsummary = getcurrentprovsummary(summary)
	if provsummary === nothing
		return DataFrame()
	end
	bm1 = provsummary.combineddata
	
	bm1start = searchsortedfirst(bm1.dateordinal, date)
	bm1end = searchsortedlast(bm1.dateordinal, date)
	
	@view bm1[bm1start:bm1end, :]
end

