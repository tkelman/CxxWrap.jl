# CxxWrap

[![Build Status](https://travis-ci.org/barche/CxxWrap.jl.svg?branch=master)](https://travis-ci.org/barche/CxxWrap.jl)
[![Build status](https://ci.appveyor.com/api/projects/status/emjnb5afswn0lq6x?svg=true)](https://ci.appveyor.com/project/barche/cxxwrap-jl)
[![CxxWrap](http://pkg.julialang.org/badges/CxxWrap_0.4.svg)](http://pkg.julialang.org/?pkg=CxxWrap)
[![CxxWrap](http://pkg.julialang.org/badges/CxxWrap_0.5.svg)](http://pkg.julialang.org/?pkg=CxxWrap)

This package aims to provide a Boost.Python-like wrapping for C++ types and functions to Julia. The idea is to write the code for the Julia wrapper in C++, and then use a one-liner on the Julia side to make the wrapped C++ library available there.

The mechanism behind this package is that functions and types are registered in C++ code that is compiled into a dynamic library. This dynamic library is then loaded into Julia, where the Julia part of this package uses the data provided through a C interface to generate functions accessible from Julia. The functions are passed to Julia either as raw function pointers (for regular C++ functions that  don't need argument or return type conversion) or std::functions (for lambda expressions and automatic conversion of arguments and return types). The Julia side of this package wraps all this into Julia methods automatically.

## What's the difference with Cxx.jl?
With Cxx.jl it is possible to directly access C++ using the `@cxx` macro from Julia. So when facing the task of wrapping a C++ library in a Julia package, authors now have 2 options:
* Use Cxx.jl to write the wrapper package in Julia code (much like one uses `ccall` for wrapping a C library)
* Use CxxWrap to write the wrapper completely in C++ (and one line of Julia code to load the .so)

Boost.Python also uses the latter (C++-only) approach, so translating existing Python bindings based on Boost.Python may be easier using CxxWrap.

## Features
* Support for C++ functions, member functions and lambdas
* Classes with single inheritance, using abstract base classes on the Julia side
* Standard-layout C++ classes can be converted to a Julia isbits immutable
* Standard-layout C++ classes can be converted to an opaque Julia bits type
* Template classes map to parametric types, for the instantiations listed in the wrapper
* Automatic wrapping of default and copy constructor (mapped to deepcopy) if defined on the wrapped C++ class

## Installation
Just like any registered package:
```julia
Pkg.add("CxxWrap")
```
### Building on Windows
To build on Windows, you need to comment [2 lines](https://github.com/barche/CxxWrap.jl/blob/master/deps/build.jl#L90-L91) from `deps/build.jl` to avoid the automatic binary download. The build prerequisites are:
- Cmake in the path
- Latest version of Visual Studio (Visual Studio 2015 Update 2 RC with MSVC 19.0.23824.1, it won't work on older versions due to internal compiler errors)

## Boost Python Hello World example
Let's try to reproduce the example from the [Boost.Python tutorial](http://www.boost.org/doc/libs/1_59_0/libs/python/doc/tutorial/doc/html/index.html). Suppose we want to expose the following C++ function to Julia in a module called `CppHello`:
```c++
std::string greet()
{
   return "hello, world";
}
```
Using the C++ side of `CxxWrap`, this can be exposed as follows:
```c++
#include <cxx_wrap.hpp>

JULIA_CPP_MODULE_BEGIN(registry)
  cxx_wrap::Module& hello = registry.create_module("CppHello");
  hello.method("greet", &greet);
JULIA_CPP_MODULE_END
```

Once this code is compiled into a shared library (say `libhello.so`) it can be used in Julia as follows:

```julia
using CxxWrap

# Load the module and generate the functions
wrap_modules(joinpath("path/to/built/lib","libhello"))
# Call greet and show the result
@show CppHello.greet()
```
The code for this example can be found in [`deps/src/examples/hello.cpp`](deps/src/examples/hello.cpp) and [`test/hello.jl`](test/hello.jl).

### Exporting symbols
Julia symbols can be exported from the module using the `export_symbols` function on the C++ side. It takes any number of symbols as string. To export `greet` from the `CppHello` module:
```c++
hello.export_symbols("greet");
```

## More extensive example and function call performance
A more extensive example, including wrapping a C++11 lambda and conversion for arrays can be found in [`deps/src/examples/functions.cpp`](deps/src/examples/functions.cpp) and [`test/functions.jl`](test/functions.jl). This test also includes some performance measurements, showing that the function call overhead is the same as using ccall on a C function if the C++ function is a regular function and does not require argument conversion. When `std::function` is used (e.g. for C++ lambdas) extra overhead appears, as expected.

## Exposing classes
Consider the following C++ class to be wrapped:
```c++
struct World
{
  World(const std::string& message = "default hello") : msg(message){}
  void set(const std::string& msg) { this->msg = msg; }
  std::string greet() { return msg; }
  std::string msg;
  ~World() { std::cout << "Destroying World with message " << msg << std::endl; }
};
```

Wrapped in the `JULIA_CPP_MODULE_BEGIN/END` block as before and defining a module `CppTypes`, the code for exposing the type and some methods to Julia is:
```c++
types.add_type<World>("World")
  .constructor<const std::string&>()
  .method("set", &World::set)
  .method("greet", &World::greet);
```
Here, the first line just adds the type. The second line adds the non-default constructor taking a string. Finally, the two `method` calls add member functions, using a pointer-to-member. The member functions become free functions in Julia, taking their object as the first argument. This can now be used in Julia as
```julia
w = CppTypes.World()
@test CppTypes.greet(w) == "default hello"
CppTypes.set(w, "hello")
@test CppTypes.greet(w) == "hello"
```

**Warning:** The ordering of the C++ code matters: types used as function arguments or return types must be added before they are used in a function.

The full code for this example and more info on immutables and bits types can be found in [`deps/src/examples/types.cpp`](deps/src/examples/types.cpp) and [`test/types.jl`](test/types.jl).

## Inheritance
See the test at [`deps/src/examples/inheritance.cpp`](deps/src/examples/inheritance.cpp) and [`test/inheritance.jl`](test/inheritance.jl).

## Template (parametric) types
The natural Julia equivalent of a C++ template class is the parametric type. The mapping is complicated by the fact that all possible parameter values must be compiled in advance, requiring a deviation from the syntax for adding a regular class. Consider the following template class:
```c++
template<typename A, typename B>
struct TemplateType
{
  typedef typename A::val_type first_val_type;
  typedef typename B::val_type second_val_type;

  first_val_type get_first()
  {
    return A::value();
  }

  second_val_type get_second()
  {
    return B::value();
  }
};
```
The code for wrapping this is:
```c++
types.add_type<Parametric<TypeVar<1>, TypeVar<2>>>("TemplateType")
  .apply<TemplateType<P1,P2>, TemplateType<P2,P1>>([](auto wrapped)
{
  typedef typename decltype(wrapped)::type WrappedT;
  wrapped.method("get_first", &WrappedT::get_first);
  wrapped.method("get_second", &WrappedT::get_second);
});
```
The first line adds the parametric type, using the generic placeholder `Parametric` and a `TypeVar` for each parameter. On the second line, the possible instantiations are created by calling `apply` on the result of `add_type`. Here, we allow for `TemplateType<P1,P2>` and `TemplateType<P2,P1>` to exist, where `P1` and `P2` are C++ classes that also must be wrapped and that fulfill the requirements for being a parameter to `TemplateType`. The argument to `apply` is a functor (generic C++14 lambda here) that takes the wrapped instantiated type (called `wrapped` here) as argument. This object can then be used as before to define methods. In the case of a generic lambda, the actual type being wrapped can be obtained using `decltype` as shown on the 4th line.

Use on the Julia side:
```julia
import ParametricTypes.TemplateType, ParametricTypes.P1, ParametricTypes.P2

p1 = TemplateType{P1, P2}()
p2 = TemplateType{P2, P1}()

@test ParametricTypes.get_first(p1) == 1
@test ParametricTypes.get_second(p2) == 1
```

Full example and test including non-type parameters at: [`deps/src/examples/parametric.cpp`](deps/src/examples/parametric.cpp) and [`test/parametric.jl`](test/parametric.jl).

## Constructors and destructors
The default constructor and any manually added constructor using the `constructor` function will automatically create a Julia object that has a finalizer attached that calls delete to free the memory. To write a C++ function that returns a new object that can be garbage-collected in Julia, use the `cxx_wrap::create` function:
```c++
cxx_wrap::create<Class>(constructor_arg1, ...);
```
This will return the new C++ object wrapped in a `jl_value_t*` that has a finalizer.

## Smart pointers
Currently, `std::shared_ptr` and `std::unique_ptr` are supported transparently. Returning one of these pointer types will return an object of type `SharedPtr{T}` (or `UniquePtr{T}`), and a `get` method is added automatically to the module that wraps `T` to extract the pointer. Example from the types test:
```c++
types.method("shared_world_factory", []()
{
  return std::shared_ptr<World>(new World("shared factory hello"));
});
```
The shared pointer can then be used in a function taking an object of type `World` like this (the module is named `CppTypes` here):
```julia
swf = CppTypes.shared_world_factory()
CppTypes.greet(CppTypes.get(swf))
```
To shorten this form, the `get` function may be exported of course. To avoid having to use the `get` function for common methods, functions taking the regular class can be overloaded in C++, like this for the `greet` method:
```c++
types.method("greet", [](const std::shared_ptr<World>& w)
{
  return w->greet();
});
```
We can then call it directly on the shared pointer:
```julia
CppTypes.greet(swf)
```

## Exceptions
When directly adding a regular free C++ function as a method, it will be called directly using ccall and any exception will abort the Julia program. To avoid this, you can force wrapping it in an `std::functor` to intercept the exception automatically by setting the `force_convert` argument to `method` to true:
```c++
mod.method("test_exception", test_exception, true);
```
Member functions and lambdas are automatically wrapped in an `std::functor` and so any exceptions thrown there are always intercepted and converted to a Julia exception.

## Working with arrays
The `ArrayRef` type is provided to work conveniently with array data from Julia. Defining a function like this in C++:
```c++
void test_array_set(cxx_wrap::ArrayRef<double> a, const int64_t i, const double v)
{
  a[i] = v;
}
```
This can be called from Julia as:
```julia
ta = [1.,2.]
test_array_set(ta, 0, 3.)
```
The `ArrayRef` type provides basic functionality:
* iterators
* `size`
* `[]` read-write accessor

## Adding Julia code to the module
Sometimes, you may want to write additional Julia code in the module that is built from C++. To do this, call the `wrap_module` method inside an appropriately named Julia module:
```julia
module ExtendedTypes

using CxxWrap
wrap_module("libextended")
export ExtendedWorld, greet

end
```
Here, `ExtendedTypes` is a name that matches the module name passed to `create_module` on the C++ side. The `wrap_module` call works as before, but now the functions and types are defined in the existing `ExtendedTypes` module, and additional Julia code such as exports and macros can be defined.

## Linking with the C++ library
The library (in [`deps/src/cxx_wrap`](deps/src/cxx_wrap)) is built using CMake, so it can be found from another CMake project using the following line in a `CMakeLists.txt`:

```cmake
find_package(CxxWrap)
```
The CMake variable `CxxWrap_DIR` should be set to the directory containing the `CxxWrapConfig.cmake`, typically `~/.julia/<Julia version>/CxxWrap/deps/usr/lib/cmake`. One can then link using:
```cmake
target_link_libraries(your_own_lib CxxWrap::cxx_wrap)
```

A complete `CMakeLists.txt` is at [`deps/src/examples/CMakeLists.txt`](deps/src/examples/CMakeLists.txt).
