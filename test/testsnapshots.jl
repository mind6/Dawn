#=
Debug specific trades or dates.
=#
using TerminalPager, Statistics, Serialization, DataFrames, Test
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

	createtraderun(@namevaluepair(test_run)..., true; ignore_cache=Type{<:Provider}[PrevDayMinuteBarProvider,BasicStatsProvider, SparseStatsProvider,AbsTradeProvider])
end

begin
	executetraderun(false)

# ctrl = Dawn.provname2provctrl[:path_a3!TSLA]

	wait4traderun()
end
begin
	Dawn.RPCClient.disconnect()
	Dawn.RPCServer.stop_server()
	wait(Threads.@spawn Dawn.RPCServer.start_server(port=8085))
	
	Dawn.RPCClient.connect(port=8085)
	Dawn.RPCClient.@rpc_import create_snapshot

end

@time ss = remote_create_snapshot(nothing);

snapsma = summarize_snapshot(ss);

begin
	Dawn.selectprovider!(snapsma, :path_a!VXX)
	Dawn.getcurrenttradeid(snapsma)
	d1 = Dawn.getcurrentdateid(snapsma)
	Dawn.nextday!(snapsma)
	d2 = Dawn.getcurrentdateid(snapsma)
	@test d1 != d2
end

#=
This code is a testing and profiling section that:
1. Extracts a DataFrame from a snapshot and analyzes its column types and sizes
2. Sets up serialization testing infrastructure with a large buffer
3. Defines a function to measure serialization time for each column in a DataFrame
4. Tests serialization/deserialization performance:
   - Processes the DataFrame with hidemissings! to prepare for serialization
   - Times the serialization of the entire DataFrame
   - Profiles memory allocations during deserialization
   - Times the restoration of missing values with unhidemissings!

This helps identify performance bottlenecks in serialization/deserialization,
particularly for DataFrames with missing values and complex column types.
=#
@noop begin

	begin

		df=ss.provider_data[1].combineddata
		bday = getfield(df.prev_bday[1],:df)
		coltypes = [(prop, typeof(getproperty(df, prop)), Base.summarysize(getproperty(df, prop))/1e6) for prop in propertynames(df)]
	end;

	begin
		buffer = Vector{UInt8}(undef, Int(3e9));
		io = IOBuffer(buffer; read=true, write=true)
	end

	measure(local_df::DataFrame) = begin
		res = DataFrame(colname=[], coltype=[], size_mb=[], serialize_time=[])
		empty!(buffer)
		for colname in propertynames(local_df)
			col = getproperty(local_df, colname)
			t = @elapsed begin
				println("Serializing $colname ...")
				Serialization.serialize(io, col)
			end
			push!(res, (colname, typeof(col), Base.summarysize(col)/1e6, t))
		end
		res
	end

	begin
		@time hidemissings!(df)
		empty!(buffer)
		mark(io)
		# @time serialize(io, df[:, 1:end-14])
		@time serialize(io, df)
		reset(io)
	end

	@profview_allocs begin
		@time deserialize(io)
	end;

	@time unhidemissings!(df);

end