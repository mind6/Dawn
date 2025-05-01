"""
Dawn is now our model controller. It is named after someone from the sixth grade. It uses StreamProviders and TwsApi to make real-time trades and handle account related things. 


In TAOF (Trading App Of the Future), account handling may be mirrored in separate processes (Multi-Dawn) to provide isolation. Actual controller updates may need to be communicated via JSON.
"""

module Dawn
export createtraderun, executetraderun, summarizetrades, deletetraderuns, selecttrade, wait4traderun, currenttraderun

# External dependencies
using  Dates, DataFrames, Infiltrator, Statistics, Distributed

# Project dependencies
using Inherit, MyFormats, MyMath, MyData
import Strategies2 as sg
import StreamProviders as sp
import StreamProviders: Provider

# Core type definitions 
include("types.jl")

#=
Dawn supports multiple TradeRunControls, though the current usage pattern seems focused on one active run at a time:
Strategy comparison - Users may want to compare results from different trading strategies or parameters
Historical backtesting - Running different date ranges with the same strategy
Progressive development - Keeping previous runs as reference points while developing new strategies
Interactive workflow - The multiple run design allows you to switch contexts during exploratory analysis
=#
const traderuns = TradeRunControl[]
selected_idx::Int = 0
const provname2provctrl = Dict{Symbol, TradeProviderControl}()

tradesummary::Union{Nothing, AbstractDataFrame} = nothing            # all trades
tradesummary_gb::Union{Nothing, GroupedDataFrame} = nothing          # grouped by :provider

monthsummary::Union{Nothing, AbstractDataFrame} = nothing            # return per month per provider
monthsummary_gb::Union{Nothing, GroupedDataFrame} = nothing          # grouped by :provider
monthsummary_combined::Union{Nothing, AbstractDataFrame} = nothing   # return per month summing all providers


"""
if selecttrade, nexttrade, or prevtrade is called, th curtrade is updated and curdate is set to reflect the date of curtrade.

if nextday or prevday is called, the curdate is updated, and curtrade is set to the first trade of curdate if any, if none it is left unchanged.
"""
curtradectrl::Union{Nothing, Dawn.TradeProviderControl} = nothing
curtradeidx::Int = -1
curdate::Union{Nothing, UnixDate} = nothing
curbday::Union{Nothing, AbstractDataFrame} = nothing  #this is a cache used by get_current_bday()

include("accessors.jl")
include("runcontrol.jl")
include("tradesummary.jl")
include("tradeselection.jl")
include("snapshots.jl")







end # module Dawn
