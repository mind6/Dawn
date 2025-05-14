"""
Minimal type definitions for snapshot data transfer
These types should be used by both server and client to ensure compatibility
"""

using DataFrames, Dates

"""
Minimal snapshot data structure for efficient RPC transfer
Contains only raw combineddata and metadata needed to reconstruct TradeRunSummary on client side
"""
struct TradeRunSnapshot
    # Raw combined data for each provider 
    provider_data::Vector{NamedTuple{(:providername, :combineddata, :refchart_colnames, :AUT), 
                                   Tuple{Symbol, DataFrame, Vector{Symbol}, String}}}
    
    # Snapshot timing information 
    snapshot_time::DateTime
    last_snapshot_time::Union{Nothing, DateTime}
    
    # Strategy prefix detected on server
    strategy_prefix::Symbol
end

export TradeRunSnapshot
