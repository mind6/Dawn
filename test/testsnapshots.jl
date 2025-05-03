#=
Debug specific trades or dates.
=#
using TerminalPager
using Revise, Dawn, MyBase, Dates, MyData
using StreamProviders
import StreamProviders as sp
import Strategies2: path_a, PlanNodeSpec, RunSpec, HistoricalRun, DateInterval

# ENV["JULIA_DEBUG"] = "StreamProviders"
ENV["JULIA_DEBUG"] = ""

test_plan = PlanNodeSpec[
	@namevaluepair(path_a) => ["VXX"]
]

test_run::RunSpec = HistoricalRun(test_plan, DateInterval(Date(2019, 8, 1), Date(2019, 9,1)))

# @profview_allocs
begin
	deletetraderuns()

	createtraderun(@namevaluepair(test_run)..., true; ignore_cache=Type{<:Provider}[BasicStatsProvider, SparseStatsProvider,AbsTradeProvider])
end

begin
	executetraderun(false)

# ctrl = Dawn.provname2provctrl[:path_a3!TSLA]

	wait4traderun()
end

ss = snapshot_summaries(nothing);

