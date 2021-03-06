# Tests for the functions library in deps/examples

println("Running functions.jl...")

using CxxWrap
using Base.Test
using Compat

const functions_lib_path = CxxWrap._l_functions

# Wrap the functions defined in C++
wrap_modules(functions_lib_path)

# Test functions from the CppHalfFunctions module
@test CppHalfFunctions.half_d(3) == 1.5
@show methods(CppHalfFunctions.half_d)
@test CppHalfFunctions.half_i(-2) == -1
@test CppHalfFunctions.half_u(3) == 1
@test CppHalfFunctions.half_lambda(2.) == 1.

# Test functions from the CppTestFunctions module
@test CppTestFunctions.concatenate_numbers(4, 2.) == "42"
@test length(methods(CppTestFunctions.concatenate_numbers)) == (Sys.WORD_SIZE == 64 ? 4 : 2) # due to overloads
@test CppTestFunctions.concatenate_strings(2, "ho", "la") == "holahola"
@test CppTestFunctions.test_int32_array(Int32[1,2])
@test CppTestFunctions.test_int64_array(Int64[1,2])
@test CppTestFunctions.test_float_array(Float32[1.,2.])
@test CppTestFunctions.test_double_array([1.,2.])
@test_throws ErrorException CppTestFunctions.test_exception()
ta = [1.,2.]
@test CppTestFunctions.test_array_len(ta) == 2
@test CppTestFunctions.test_array_get(ta, Int64(0)) == 1.
@test CppTestFunctions.test_array_get(ta, Int64(1)) == 2.
CppTestFunctions.test_array_set(ta, Int64(0), 3.)
CppTestFunctions.test_array_set(ta, Int64(1), 4.)
@test ta[1] == 3.
@test ta[2] == 4.
@test CppTestFunctions.test_type_name("IO") == "IO"

# Performance tests
const test_size = 50000000
const numbers = rand(test_size)
output = zeros(test_size)

# Build a function to loop over the test array
function make_loop_function(name)
    fname = Symbol(:half_loop_,name,:!)
    inner_name = Symbol(:half_,name)
    @eval begin
        function $(fname)(n::Array{Float64,1}, out_arr::Array{Float64,1})
            test_length = length(n)
          for i in 1:test_length
                out_arr[i] = $(inner_name)(n[i])
          end
        end
    end
end

# Julia version
half_julia(d::Float64) = d*0.5

# C version
half_c(d::Float64) = ccall((:half_c, functions_lib_path), Cdouble, (Cdouble,), d)

# Bring C++ versions into scope
using CppHalfFunctions.half_d, CppHalfFunctions.half_lambda, CppHalfFunctions.half_loop_cpp!

# Make the looping functions
make_loop_function(:julia)
make_loop_function(:c)
make_loop_function(:d) # C++ with regular C++ function pointer
make_loop_function(:lambda) # C++ lambda, so using std::function

# test that a "half" function does what it should
function test_half_function(f)
  input = [2.]
  output = [0.]
  f(input, output)
  @test output[1] == 1.
end
test_half_function(half_loop_julia!)
test_half_function(half_loop_c!)
test_half_function(half_loop_d!)
test_half_function(half_loop_lambda!)
test_half_function(half_loop_cpp!)

# Run timing tests
println("---- Half test timings ----")
println("Julia test:")
@time half_loop_julia!(numbers, output)
@time half_loop_julia!(numbers, output)
@time half_loop_julia!(numbers, output)

println("C test:")
@time half_loop_c!(numbers, output)
@time half_loop_c!(numbers, output)
@time half_loop_c!(numbers, output)

println("C++ test:")
@time half_loop_d!(numbers, output)
@time half_loop_d!(numbers, output)
@time half_loop_d!(numbers, output)

println("C++ lambda test:")
@time half_loop_lambda!(numbers, output)
@time half_loop_lambda!(numbers, output)
@time half_loop_lambda!(numbers, output)

println("C++ test, loop in the C++ code:")
@time half_loop_cpp!(numbers, output)
@time half_loop_cpp!(numbers, output)
@time half_loop_cpp!(numbers, output)
