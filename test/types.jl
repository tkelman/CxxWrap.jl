# Hello world example, similar to the Boost.Python hello world

println("Running types.jl...")

using CxxWrap
using Base.Test
using Compat

# Wrap the functions defined in C++
wrap_modules(CxxWrap._l_types)

using CppTypes
using CppTypes.World

# Stress test
for i in 1:1000000
  d = CppTypes.DoubleData()
end

# Default constructor
@test World <: CxxWrap.CppAny
@test supertype(World) == CxxWrap.CppAny
w = World()
println("Dumping type w...")
dump(w)
@test CppTypes.greet(w) == "default hello"

@show fw = CppTypes.world_factory()
@test CppTypes.greet(fw) == "factory hello"

@show swf = CppTypes.shared_world_factory()
@test CppTypes.greet(swf) == "shared factory hello" # Uses the shared ptr overload
@test CppTypes.greet(CppTypes.get(swf)) == "shared factory hello" # Explicitly get the shared ptr

@show uwf = CppTypes.unique_world_factory()
@test CppTypes.greet(CppTypes.get(uwf)) == "unique factory hello"

CppTypes.set(w, "hello")
@show CppTypes.greet(w)
@test CppTypes.greet(w) == "hello"

w = World("constructed")
@test CppTypes.greet(w) == "constructed"

w_assigned = w
w_deep = deepcopy(w)

@test w_assigned == w
@test w_deep != w

# Destroy w: w and w_assigned should be dead, w_deep alive
finalize(w)
println("finalized w")
@test_throws ErrorException CppTypes.greet(w)
println("throw test 1 passed")
@test_throws ErrorException CppTypes.greet(w_assigned)
println("throw test 2 passed")
@test CppTypes.greet(w_deep) == "constructed"
println("completed deepcopy test")

noncopyable = CppTypes.NonCopyable()
println("noncopyable constructed")
@test_throws ErrorException other_noncopyable = deepcopy(noncopyable)

println("completed noncopyable test")

import CppTypes.ImmutableDouble

@test sizeof(ImmutableDouble) == 8
@test isbits(ImmutableDouble)
@test length(fieldnames(ImmutableDouble)) == 1
println("creating bitsval1")
bitsval1 = ImmutableDouble(1)
println("created bitsval1")
@test bitsval1.value == 1.
@test bitsval1 == 1.
@test CppTypes.getvalue(bitsval1) == 1
bitsval2 = CppTypes.ImmutableDouble(2)
@test bitsval2 == 2
@test typeof(bitsval1 + bitsval2) == CppTypes.ImmutableDouble
@test (bitsval1 + bitsval2) == 3.

println("creating bc")
bc = make_bits(1, 2)
println("created bc")
@test sizeof(bc)==16
@test get_bits_a(bc)==1
@test get_bits_b(bc)==2
