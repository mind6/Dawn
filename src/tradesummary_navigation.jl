#=
Functions for navigating trades within a TradeRunSummary.

These functions replace the older navigation functions that worked with TradeRunContext.
The navigation state now lives with the TradeRunSummary, making it self-contained for RPC.
=#

"""
Select a trade for navigation in the summary.

# Arguments
- `summary`: The TradeRunSummary to navigate
- `timeoftrade`: Optional DateTime to select a specific trade, default is the first trade
- `provname`: Optional Symbol to select a specific provider, default is the first provider

# Returns
Tuple of (provider_name, trade_datetime)
"""
function selecttrade!(summary::TradeRunSummary, timeoftrade::Union{Nothing, DateTime}=nothing; 
                      provname::Union{Nothing, Symbol}=nothing)
	# Set the current provider
	if provname !== nothing
		summary.curtradectrl_name = provname
	elseif summary.curtradectrl_name === nothing && !isempty(summary.provider_summaries)
		summary.curtradectrl_name = summary.provider_summaries[1].providername
	end
	
	if summary.curtradectrl_name === nothing
		error("No provider selected or available")
	end
	
	# Get the provider summary
	if !haskey(summary.provname2summary, summary.curtradectrl_name)
		error("No summary found for provider $(summary.curtradectrl_name)")
	end
	provsummary = summary.provname2summary[summary.curtradectrl_name]
	
	if isempty(provsummary.trades)
		error("No trades found for provider $(summary.curtradectrl_name)")
	end
	
	# Set the trade index
	summary.curtradeidx = timeoftrade === nothing ? 1 : MyData.getloc(provsummary.trades, timeoftrade)
	
	# Set the date
	summary.curdate = provsummary.trades[summary.curtradeidx, :dateordinal]
	
	return (summary.curtradectrl_name, provsummary.trades[summary.curtradeidx, :datetime])
end

"""
Navigate to next/previous trade (cycles around).

# Arguments
- `summary`: The TradeRunSummary to navigate
- `offset`: 1 for next trade, -1 for previous trade

# Returns
Tuple of (provider_name, trade_datetime)
"""
function nexttrade!(summary::TradeRunSummary, offset::Int=1)
	if summary.curtradectrl_name === nothing
		error("No provider selected. Call selecttrade! first")
	end
	
	provsummary = summary.provname2summary[summary.curtradectrl_name]
	if isempty(provsummary.trades)
		error("No trades found for current provider")
	end
	
	summary.curtradeidx = MyMath.modind(summary.curtradeidx + offset, nrow(provsummary.trades))
	summary.curdate = provsummary.trades[summary.curtradeidx, :dateordinal]
	
	return (summary.curtradectrl_name, provsummary.trades[summary.curtradeidx, :datetime])
end

"""
Navigate to previous trade.

# Returns
Tuple of (provider_name, trade_datetime)
"""
function prevtrade!(summary::TradeRunSummary)
	nexttrade!(summary, -1)
end

"""
Navigate to next/previous day.

# Arguments
- `summary`: The TradeRunSummary to navigate
- `offset`: 1 for next day, -1 for previous day

# Returns
Tuple of (provider_name, day)
"""
function nextday!(summary::TradeRunSummary, offset::Int=1)
	if summary.curtradectrl_name === nothing || summary.curdate === nothing
		error("No provider or date selected. Call selecttrade! first")
	end
	
	provsummary = summary.provname2summary[summary.curtradectrl_name]
	bm1 = provsummary.combineddata
	
	if offset > 0
		ind = searchsortedfirst(bm1.dateordinal, summary.curdate) + offset
	else
		ind = searchsortedlast(bm1.dateordinal, summary.curdate) + offset
	end
	
	summary.curdate = bm1.dateordinal[ind]
	
	# Try to sync to a trade on this day
	dft = provsummary.trades
	trade_ind = searchsortedfirst(dft.dateordinal, summary.curdate)
	if trade_ind ∈ 1:nrow(dft) && dft.dateordinal[trade_ind] == summary.curdate
		summary.curtradeidx = trade_ind
	end
	
	return (summary.curtradectrl_name, summary.curdate)
end

"""
Navigate to previous day.

# Returns
Tuple of (provider_name, day)
"""
function prevday!(summary::TradeRunSummary)
	nextday!(summary, -1)
end

"""
Switch to another provider.

# Arguments
- `summary`: The TradeRunSummary to navigate
- `provname`: Symbol of the provider to select

# Returns
Tuple of (provider_name, trade_datetime)
"""
function selectprovider!(summary::TradeRunSummary, provname::Symbol)
	if !haskey(summary.provname2summary, provname)
		error("Provider $provname not found in summary")
	end
	
	summary.curtradectrl_name = provname
	
	# Reset to first trade
	provsummary = summary.provname2summary[provname]
	if isempty(provsummary.trades)
		summary.curtradeidx = 0
		summary.curdate = nothing
		return (provname, nothing)
	else
		summary.curtradeidx = 1
		summary.curdate = provsummary.trades[1, :dateordinal]
		return (provname, provsummary.trades[1, :datetime])
	end
end

"""
Get current trade from summary.
"""
function getcurrenttrade(summary::TradeRunSummary)
	if summary.curtradectrl_name === nothing || summary.curtradeidx == 0
		return nothing
	end
	
	provsummary = summary.provname2summary[summary.curtradectrl_name]
	provsummary.trades[summary.curtradeidx, :]
end

"""
Get current provider from summary.
"""
function getcurrentprovider(summary::TradeRunSummary)
	summary.curtradectrl_name
end

"""
Get current trade id from summary.
"""
function getcurrenttradeid(summary::TradeRunSummary)
	if summary.curtradectrl_name === nothing || summary.curtradeidx == 0
		return nothing
	end
	
	provsummary = summary.provname2summary[summary.curtradectrl_name]
	(summary.curtradectrl_name, provsummary.trades[summary.curtradeidx, :datetime])
end

"""
Get current date id from summary.
"""
function getcurrentdateid(summary::TradeRunSummary)
	if summary.curtradectrl_name === nothing || summary.curdate === nothing
		return nothing
	end
	
	(summary.curtradectrl_name, summary.curdate)
end

"""
Get current day's minute bars from summary.
"""
function get_current_bm1(summary::TradeRunSummary)
	if summary.curtradectrl_name === nothing || summary.curdate === nothing
		return DataFrame()
	end
	
	provsummary = summary.provname2summary[summary.curtradectrl_name]
	bm1 = provsummary.combineddata
	
	bm1start = searchsortedfirst(bm1.dateordinal, summary.curdate)
	bm1end = searchsortedlast(bm1.dateordinal, summary.curdate)
	
	@view bm1[bm1start:bm1end, :]
end

"""
Get two days of minute bars from summary.
"""
function get_twodays_bm1(summary::TradeRunSummary)
	if summary.curtradectrl_name === nothing || summary.curdate === nothing
		return DataFrame()
	end
	
	provsummary = summary.provname2summary[summary.curtradectrl_name]
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
	subdf = summary.tradesummary_gb[(provider, )]
	subdf[MyData.getloc(subdf.datetime, datetime), :]
end


"""
Get a row from combined data by datetime.
"""
function get_bm1_row(summary::TradeRunSummary, provname::Symbol, datetime::DateTime)
	if !haskey(summary.provname2summary, provname)
		error("No summary found for provider $provname")
	end
	provsummary = summary.provname2summary[provname]
	df = provsummary.combineddata
	df[MyData.getloc(df, datetime), :]
end

"""
Get a range of minute bars from combined data.
"""
function get_bm1_rows(summary::TradeRunSummary, provname::Symbol, date::UnixDate)
	if !haskey(summary.provname2summary, provname)
		error("No summary found for provider $provname")
	end
	provsummary = summary.provname2summary[provname]
	bm1 = provsummary.combineddata
	
	bm1start = searchsortedfirst(bm1.dateordinal, date)
	bm1end = searchsortedlast(bm1.dateordinal, date)
	
	@view bm1[bm1start:bm1end, :]
end

"""
Get all trade rows for a provider.
"""
function get_trades(summary::TradeRunSummary, provname::Symbol)
	if !haskey(summary.provname2summary, provname)
		error("No summary found for provider $provname")
	end
	provsummary = summary.provname2summary[provname]
	provsummary.trades
end
