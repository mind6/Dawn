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
	executetraderun(false)

# ctrl = Dawn.provname2provctrl[:path_a3!TSLA]

	wait4traderun()
end
begin
	Dawn.RPCClient.disconnect()
	Dawn.RPCServer.stop_server()
	wait(Threads.@spawn Dawn.RPCServer.start_server(port=8082))
	
	Dawn.RPCClient.connect(port=8082)
	Dawn.RPCClient.@rpc_import create_snapshot

end

@time ss = remote_create_snapshot(nothing);

snapsummary = summarize_snapshot(ss);

function Serialization.deserialize_array(s::AbstractSerializer)
    slot = s.counter; s.counter += 1
    d1 = deserialize(s)
    if isa(d1, Type)
        elty = d1
        d1 = deserialize(s)
    else
        elty = UInt8
    end
    if isa(d1, Int32) || isa(d1, Int64)
        if elty !== Bool && isbitstype(elty)
            a = Vector{elty}(undef, d1)
            s.table[slot] = a
            return read!(s.io, a)
        end
        dims = (Int(d1),)
    elseif d1 isa Dims
        dims = d1::Dims
    else
        dims = convert(Dims, d1::Tuple{Vararg{OtherInt}})::Dims
    end
    if isbitstype(elty)
        n = prod(dims)::Int
        if elty === Bool && n > 0
            A = Vector{Bool}(undef, n)
            i = 1
            while i <= n
                b = read(s.io, UInt8)::UInt8
                v::Bool = (b >> 7) != 0
                count = b & 0x7f
                nxt = i + count
                while i < nxt
                    A[i] = v
                    i += 1
                end
            end
        else
            A = read!(s.io, Array{elty}(undef, dims))
        end
        s.table[slot] = A
        return A
    end
    A = Array{elty, length(dims)}(undef, dims)
    s.table[slot] = A
    sizehint!(s.table, s.counter + div(length(A)::Int,4))
    Serialization.deserialize_fillarray!(A, s)
    return A
end

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

@profview_allocs 

begin
	@time deserialize(io)
end;

@time unhidemissings!(df);

begin
	@time hidemissings!(df)
	res = measure(df)
	@time unhidemissings!(df)
	res
end

begin
	N = Int(1e6);
	i = rand(Bool,N);
	sum_i = sum(i);
	@time begin 
		a = Vector{Union{Int,Missing}}(missing, N);
		a[i] .= 1:sum_i;
	end
	@time begin 
		a = Vector{Union{Int,Missing}}(undef, N);
		a[(!).(i)] .= missing;
		a[i] .= 1:sum_i;
	end
end;

begin
	df2 = copy(df)
	@assert isequal(df, df2)

	@time Serialization.serialize(io, df);
	GC.gc()
	@time begin
		hidemissings!(df2)
		Serialization.serialize(io, df2)
		unhidemissings!(df2)
	end	
	@assert isequal(df, df2)
end;

begin
	bday = getfield(df.prev_bday[1],:df)
	@time prevbday = [r === missing ? missing : getfield(r, :rownumber) for r in df.prev_bday]
	@time begin
		Serialization.serialize(io, prevbday)
		Serialization.serialize(io, bday)
	end
end


prevbday = collect(skipmissing(df.prev_bday))
f2(v) = begin
	res = Vector{Int}(undef, nrow(v));
	@time for i in 1:nrow(v)
		# res[i] = DataFrames.row(vv[i]);
		res[i] = round(v[i, :open])
	end
	res
end
x = prevbday[120000:160000] 
x2 = prevbday[1:40000]
f2(bday);

bday2 = Tables.columntable(bday)
rows = [bday2[i, :] for i in 1:nrow(bday2)]

@time DataFrames.row(prevbday[58839]);
@time DataFrames.row(prevbday[58840]);

#TODO: allocations on array access has something to do with global scope
# https://docs.julialang.org/en/v1/manual/performance-tips/index.html#Avoid-global-variables-1
f2() = begin
	x = [1,2,3.0]
	f3(x)
end
f3(x) = begin
	@btime x[1]+1
end
f2()
