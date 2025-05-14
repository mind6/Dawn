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