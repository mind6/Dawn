#=
This file helps us figure out a potentially faster serialization method for Dawn.TradeRunSummary.

https://stackoverflow.com/questions/49007433/how-to-implement-custom-serialization-deserialization-for-a-struct-in-julia

=#

using Serialization

# The target struct
struct Foo
    x::Int
    y::Union{Int, Nothing} #we do not want to serialize this field
end

# Custom Serialization of a Foo instance
function Serialization.serialize(s::AbstractSerializer, instance::Foo)
    Serialization.writetag(s.io, Serialization.OBJECT_TAG)
    Serialization.serialize(s, Foo)
    Serialization.serialize(s, instance.x)
end

# Custom Deserialization of a Foo instance
function Serialization.deserialize(s::AbstractSerializer, ::Type{Foo})
    x = Serialization.deserialize(s)
    Foo(x,nothing)
end

foo1 = Foo(1,2)

# Serialization
write_iob = IOBuffer()
serialize(write_iob, foo1)
seekstart(write_iob)
content = read(write_iob)

# Deserialization
read_iob = IOBuffer(content)
foo2 = deserialize(read_iob)

@show foo1
@show foo2 

@assert Union{Int,String,Float64,Missing}.a == Missing "If a union type contains Missing, it is always the first type in the union."


begin
	function Serialization.serialize(s::AbstractSerializer, df::DataFrame)
		#hide missings by replacing them with 0, and record the positions of the missings
		for col in names(df)
			if eltype(df[!, col]) <: Union{T, Missing} where T
				x, i = hide_missings!(df[!, col])
				df[!, Symbol(:HIDDEN_MISSINGS_, col)] = i
			end
		end
		Serialization.serialize(s, df)
  end
  
  # Custom Deserialization of a Foo instance
  function Serialization.deserialize(s::AbstractSerializer, ::Type{DataFrame})
		df = Serialization.deserialize(s)
		return df
	end
end

#TODO: instead of overriding serialization, add hide/unhide methods to DataFrame and for customcontainers like TradeRunSnapshot
begin

	hide_missings!(x::AbstractVector{Union{T, Missing}}) where T = begin
		i = ismissing.(x)
		x[i] .= 0
		return x, i
	end
	unhide_missings!(x::AbstractVector{Union{T, Missing}}, i::AbstractVector{Bool}) where T = begin
		x[i] .= missing
		return x
	end

	mytest() = begin
		N = Int(1e8);
		buffer = Vector{UInt8}(undef, 16 * N);
		io = IOBuffer(buffer, write=true)
		
		test_cases = [
			("BitArray of trues", BitArray(true for i in 1:N)),
			("Array of zeros (Int)", zeros(Int, N)),
			("Array of rands (Int)", rand(Int, N)),
			("Uninitialized Vector{Int}", Vector{Int}(undef, N)),
			("Array of zeros (Union{Int, Float64})", zeros(Union{Int, Float64}, N)),
			("Array of zeros (Union{Int, Missing})", zeros(Union{Int, Missing}, N)),
			("Array of missings (Missing)", Vector{Missing}(missing, N)),
			("Array of missings (Union{Int, Missing})", Vector{Union{Int, Missing}}(missing, N)),
			("Array of 50% missings (Union{Int, Missing})", begin
				arr = Vector{Union{Int, Missing}}(missing, N)
				inds = rand(1:N, N÷2)
				arr[inds] .= inds
				arr
			end),
			("Wrapped Array of missings (Union{Int, Missing})", hide_missings!(Vector{Union{Int, Missing}}(missing, N))),
			("Uninitialized Vector{Union{Int, Float64}}", Vector{Union{Int, Float64}}(undef, N))
		]
		
		for (desc, arr) in test_cases
			println("\n$desc:")
			empty!(buffer)
			@time Serialization.serialize(io, arr)
		end
		
	end

	mytest()

end