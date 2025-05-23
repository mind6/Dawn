#=
runs scripts that produce data, which would look cleaner here than in a notebook or in another package.
=#
using TerminalPager
using Revise, Dawn
using StreamProviders
import StreamProviders as sp

# ENV["JULIA_DEBUG"] = "StreamProviders"
ENV["JULIA_DEBUG"] = ""

# @profview_allocs
begin
	deletetraderuns()

	# createtraderun(:run_a3_1, true)
	createtraderun(:run_a3_1, true; ignore_cache=Type{<:Provider}[BasicStatsProvider, SparseStatsProvider,AbsTradeProvider])

	executetraderun()

# ctrl = Dawn.provname2provctrl[:path_a3!TSLA]

	wait4traderun()
end


begin
	Dawn.RPCServer.stop_server()
	wait(Threads.@spawn Dawn.RPCServer.start_server(port=8081))
end
