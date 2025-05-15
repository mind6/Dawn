"""
Dawn is now our model controller. It is named after someone from the sixth grade. It uses StreamProviders and TwsApi to make real-time trades and handle account related things. 


In TAOF (Trading App Of the Future), account handling may be mirrored in separate processes (Multi-Dawn) to provide isolation. Actual controller updates may need to be communicated via JSON.
"""

module Dawn
export createtraderun, executetraderun, summarizetrades, deletetraderuns, selecttraderun, wait4traderun, currenttraderun, snapshot_summaries, TradeRunSummary, TradeProviderSummary, TradeRunSnapshot

# External dependencies
using  Dates, DataFrames, Infiltrator, Statistics, Distributed, ProgressMeter, RPC

# Project dependencies
using Inherit, MyFormats, MyMath, MyData
import Strategies2 as sg
import StreamProviders as sp
import StreamProviders: Provider

# Core type definitions 
include("snapshot_types.jl")
include("types.jl")

#=
Dawn supports multiple TradeRunContext objects, allowing:
- Strategy comparison - Users may want to compare results from different trading strategies or parameters
- Historical backtesting - Running different date ranges with the same strategy
- Progressive development - Keeping previous runs as reference points while developing new strategies
- Interactive workflow - The multiple run design allows you to switch contexts during exploratory analysis
=#
const traderuns = TradeRunContext[]
selected_idx::Int = 0

include("runcontrol.jl")
include("accessors.jl")
include("snapshots.jl")
include("tradesummary.jl")
include("tradeselection.jl")
include("snapshot_client_v2.jl")
const RPC_PORT = 8083


@postinit function __myinit__()
	if !Inherit.isprecompiling()
		RPCServer.start_server("127.0.0.1", RPC_PORT)

		#=
		Exports must be registered on runtime instance of RPCServer. This means we must do it in the module init function. If we registered in the module global scope, it would be registered on the precompiled module, not the runtime instance.

		The reason registration is needed is because the RPCServer cannot know about every module containing functions that might be called. Such functions need to be registered with the RPCServer.
		=#
		RPCServer.@rpc_export snapshot_summaries
	end
end

end
