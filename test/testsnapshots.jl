#=
Debug specific trades or dates.
=#
using TerminalPager, Statistics, Serialization, DataFrames
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

	createtraderun(@namevaluepair(test_run)..., false; ignore_cache=Type{<:Provider}[BasicStatsProvider, SparseStatsProvider,AbsTradeProvider])
end

begin
	executetraderun(true)

# ctrl = Dawn.provname2provctrl[:path_a3!TSLA]

	wait4traderun()
end

ss = create_snapshot(nothing);

snapsummary = summarize_snapshot(ss);

begin

	df=ss.provider_data[1].combineddata
	bday = getfield(df.prev_bday[1],:df)
end;

begin
	N = Int(1e8);
	buffer = Vector{UInt8}(undef, 16 * N);
	io = IOBuffer(buffer, write=true)
	df2 = copy(df)
	@assert isequal(df, df2)

	@time Serialization.serialize(io, df);
	GC.gc()
	@time begin
		hide_missings!(df2)
		Serialization.serialize(io, df2)
		unhide_missings!(df2)
	end	
	@assert isequal(df, df2)
end;
