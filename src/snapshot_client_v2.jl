"""
Client-side reconstruction of TradeRunSummary from minimal TradeRunSnapshot data
This module should be used on the client side that receives the TradeRunSnapshot via RPC
"""
module SnapshotClient

using DataFrames, Dates, Statistics
import MyMath, MyFormats

# Import the TradeRunSnapshot type (this should match the server definition)
include("snapshot_types.jl")

"""
Client-side function to reconstruct TradeRunSummary from TradeRunSnapshot
"""
function reconstruct_summary_from_snapshot(snapshot::TradeRunSnapshot, 
                                         TradeProviderSummary, 
                                         TradeRunSummary,
                                         create_monthly_summaries,
                                         sp)
    provider_summaries = TradeProviderSummary[]
    provname2summary = Dict{Symbol, TradeProviderSummary}()
    
    # Process each provider's data
    for prov_data in snapshot.provider_data
        # Extract trades from combineddata
        trades = filter(:exitstrat_onenter => !ismissing, prov_data.combineddata)
        
        # Create exitres dataframe 
        exitres = DataFrame(provider=Symbol[], datetime=DateTime[], tradeaction=MyFormats.TradeAction[])
        exitprefixes = Set{Symbol}()
        
        for trade_row in eachrow(trades)
            # Start building the row
            newrow = Pair{Symbol, Any}[
                :provider => prov_data.providername,
                :AUT_close => trade_row.close,
                :datetime => trade_row.datetime
            ]
            
            # Add tradeaction if present
            if hasproperty(trade_row, :tradeaction) && !ismissing(trade_row.tradeaction)
                push!(newrow, :tradeaction => trade_row.tradeaction)
            end
            
            # Add reference columns
            for colname in prov_data.refchart_colnames
                if hasproperty(trade_row, colname)
                    push!(newrow, colname => trade_row[colname])
                end
            end
            
            # Process exit strategies
            for strat in trade_row.exitstrat_onenter
                pre = sp.typeprefix(strat)
                push!(newrow, Symbol(pre, :_frac_return) => strat.frac_return)
                push!(newrow, Symbol(pre, :_log_return) => strat.log_return)
                push!(newrow, Symbol(pre, :_dollar_profit) => strat.dollar_profit)
                push!(newrow, Symbol(pre, :_elapsed) => strat.elapsed)
                push!(exitprefixes, pre)
            end
            
            push!(exitres, NamedTuple(newrow); cols=:union)
        end
        
        # Set metadata
        metadata!(trades, "symbol", prov_data.AUT; style=:note)
        metadata!(prov_data.combineddata, "symbol", prov_data.AUT; style=:note)
        
        # Create provider summary
        summary = TradeProviderSummary(
            prov_data.providername,
            prov_data.refchart_colnames,
            prov_data.combineddata, # Keep full combineddata for functions like get_twodays_bm1
            trades,
            exitres,
            exitprefixes
        )
        
        push!(provider_summaries, summary)
        provname2summary[summary.providername] = summary
    end
    
    # Generate trade summaries
    retcol = Symbol(snapshot.strategy_prefix, :_log_return)
    profit_col = Symbol(snapshot.strategy_prefix, :_dollar_profit)
    
    all_exitres = [summary.exitres for summary in provider_summaries]
    
    # Create merged trade summary
    tradesummary = if !isempty(all_exitres)
        df = vcat(all_exitres...; cols=:union)
        sort!(df, :datetime)
        
        # Add month column and cumulative metrics
        df.month = Dates.floor.(df.datetime, Dates.Month)
        transform!(df, retcol => cumsum => :combined_cumret)
        
        # Add metadata if calculations are possible
        if !isempty(df) && retcol in propertynames(df) && profit_col in propertynames(df)
            if !all(ismissing, df[!, retcol])
                sortino_val = MyMath.sortinoratio_annualized(df; logret_col=retcol)
                if !isempty(sortino_val)
                    metadata!(df, "sortinoratio", sortino_val[1]; style=:note)
                end
            end
            metadata!(df, "dollar_profit", mean(skipmissing(df[!, profit_col])); style=:note)
            metadata!(df, "log_ret", mean(skipmissing(df[!, retcol])); style=:note)
        end
        df
    else
        DataFrame()
    end
    
    # Create grouped summaries
    tradesummary_byprov = if !isempty(tradesummary) && :provider in propertynames(tradesummary)
        gdf = groupby(tradesummary, :provider)
        if retcol in propertynames(tradesummary)
            transform!(gdf, retcol => cumsum => :provider_cumret)
        end
        gdf
    else
        groupby(DataFrame(provider=Symbol[]), :provider)
    end
    
    # Create monthly summaries
    monthsummary, monthsummary_byprov, monthsummary_combined = if !isempty(tradesummary) && retcol in propertynames(tradesummary)
        create_monthly_summaries(tradesummary, retcol)
    else
        DataFrame(), groupby(DataFrame(provider=Symbol[]), :provider), DataFrame()
    end
    
    return TradeRunSummary(
        provider_summaries,
        provname2summary,
        snapshot.last_snapshot_time,
        tradesummary,
        tradesummary_byprov,
        monthsummary,
        monthsummary_byprov,
        monthsummary_combined,
        nothing,  # curtradectrl_name
        0,        # curtradeidx
        nothing,  # curdate
        nothing   # curbday
    )
end

"""
Convenience wrapper for client-side usage that receives snapshot via RPC
"""
function process_snapshot(snapshot::TradeRunSnapshot; 
                         TradeProviderSummary=TradeProviderSummary,
                         TradeRunSummary=TradeRunSummary, 
                         create_monthly_summaries=create_monthly_summaries,
                         sp=sp)
    return reconstruct_summary_from_snapshot(snapshot, 
                                           TradeProviderSummary, 
                                           TradeRunSummary, 
                                           create_monthly_summaries, 
                                           sp)
end

end # module
