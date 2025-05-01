"""
Dawn is now our model controller. It is named after someone from the sixth grade. It uses StreamProviders and TwsApi to make real-time trades and handle account related things. 


In TAOF (Trading App Of the Future), account handling may be mirrored in separate processes (Multi-Dawn) to provide isolation. Actual controller updates may need to be communicated via JSON.
"""

module Dawn
export createtraderun, executetraderun, summarizetrades, deletetraderuns, selecttraderun, wait4traderun, currenttraderun

# External dependencies
using  Dates, DataFrames, Infiltrator, Statistics, Distributed

# Project dependencies
using Inherit, MyFormats, MyMath, MyData
import Strategies2 as sg
import StreamProviders as sp
import StreamProviders: Provider

# Core type definitions 
include("types.jl")

# Global trade context - contains all state previously stored as globals
const tradecontext = TradeRunContext()

include("runcontrol.jl")
include("accessors.jl")
include("snapshots.jl")
include("tradeselection.jl")
include("tradesummary.jl")

end
