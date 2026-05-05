#import "ctufit-thesis.typ": *

= Julia TNL bindings

// https://docs.julialang.org/en/v1/
Julia programming language is a flexible dynamic language with performance comparable to traditional statically typed languages like #cpp. To achieve good performance, Julia relies on type inference and just-in-time compilation using the LLVM framework. What's more, among languages advantages authors of Julia list "No need to vectorize code for performance; devectorized code is fast", "Designed for parallelism and distributed computation", "Powerful shell-like capabilities for managing other processes" or even "Call C functions directly (no wrappers or special APIs needed)". #mcite(<c_julia_siam_article>, <c_julia_docs>)

All these features all make Julia a very attractive candidate for new TNL frontend and might even sidestep some of the challenges encountered in PyTNL. The native JIT compilation options could make it possible to write user-defined functions directly in Julia and still achieve good performance, without the need for a separate third-party tool like Numba. 

With Julia being closer to statically typed languages and its claims about fast, devectorized code, it would be worth revisiting the more straightforward callback interface as described in @pytnl_nanobind_callbacks. 

Unlike PyTNL, the jTNL package did not exist prior to this work and unfortunately could not be implemented within the scope of this thesis either. Instead, this chapter outlines potential approaches to Julia bindings and proposes a realistic initialization path for starting such a project.

== Native capabilities

// https://docs.julialang.org/en/v1/manual/calling-c-and-fortran-code/
Julia can call C and Fortran functions directly through `@ccall` macro provided the wanted code is available in a shared library. The macro can then be wrapped in a Julia function to provide a more Julian API. 

#code1([Wrapping a `@ccall` to C `getenv` function into a Julia function. #cite(<c_julia_docs>)], none, 
```jl
function getenv(var::AbstractString)
    val = @ccall getenv(var::Cstring)::Cstring
    if val == C_NULL
        error("getenv: undefined variable: ", var)
    end
    return unsafe_string(val)
end

julia> getenv("SHELL")
"/bin/bash"

julia> getenv("FOOBAR")
ERROR: getenv: undefined variable: FOOBAR
```
)

What's more, Julia natively also exposes a `@cfunction` macro for creating C-compatible function pointers from Julia functions. When combined with `@ccall`, this allows Julia code to be used as a callback in the C API. An example of this is shown in the documentation for using `qsort` from the C standard library:

#code1([Creating a C-compatible callback from a Julia function. #cite(<c_julia_docs>)], none, 
```jl
julia> function mycompare(a, b)::Cint
           return (a < b) ? -1 : ((a > b) ? +1 : 0)
       end;
julia> mycompare_c = @cfunction(mycompare, Cint, (Ref{Cdouble}, Ref{Cdouble}));
julia> A = [1.3, -2.7, 4.4, 3.1];

julia> @ccall qsort(A::Ptr{Cdouble}, length(A)::Csize_t, sizeof(eltype(A))::Csize_t, mycompare_c::Ptr{Cvoid})::Cvoid

julia> A
4-element Vector{Float64}:
 -2.7
  1.3
  3.1
  4.4
```)

Building a jTNL package only around these native capabilities however would be rather limiting. The `@ccall` macro is designed specifically for C APIs, so it cannot directly expose #cpp classes, templates or overloaded methods. Building jTNL would therefore require a C compatibility layer around only selected TNL functionality.

A more promising approach would therefore be using some of the existing Julia libraries for #cpp binding that could expose the TNL's API more directly.

== Bindings libraries

Four Julia packages are particularly relevant when considering how such a wrapper could be initialized.

=== C Binding libraries

For completeness, libraries that focus on generating bindings for only C APIs are also explored. For all of them however, the main drawback is always present: they would require a C compatibility layer to be implemented in front of TNL. That would be not only a significant amount of work, but it would also erase much of TNL's rich type structure. 

==== `CBinding.jl`

// https://github.com/analytech-solutions/CBinding.jl
`CBinding.jl` is a Julia package that can automate the generation of Julia bindings from C code and headers. Instead of writing the `@ccall` wrappers manually, the library uses Clang frontend to parse supplied C headers, or even supplied strings of C declarations. This is a big time saver compared to writing the bindings by hand as it can automatically generate bindings even for more complex APIs, including those with nested types. #cite(<c_cbinding_github>)

Maintaining the bindings is also easier with `CBinding.jl` because the bindings can be regenerated whenever the C API changes, without needing to adjust all the `@ccall` wrappers. 

The library then also provides a convenient `c"..."` macro that allows referring to any of the C types or functions directly in Julia code. Without the need to specify the expected argument and return types.

#code1([Example of using `CBinding.jl` to generate bindings for a C library. #cite(<c_cbinding_github>)], none,
```jl
julia> module MyLib  # generally some C bindings are defined elsewhere
         using CBinding
         
         c`-std=c99 -Wall -Imy/include`
         
         c"""
           struct S;
           struct T {
             int i;
             struct S *s;
             struct T *t;
           };
           
           extern void func(struct S *s, struct T t);
         """
       end

julia> using CBinding, .MyLib

julia> c"struct T" <: Cstruct
true

julia> t = c"struct T"(i = 123);

julia> t.i
123
```)

The Clang compiler is only used for parsing and translation. The implementation still must be compiled beforehand and be available as a shared library. This is in fact a good fit as it allows the implementation to be compiled even by `nvcc` and the usage of device code.

==== `Clang.jl`

// https://github.com/juliainterop/clang.jl
Compared to `CBinding.jl` which translates given C declarations at runtime, `Clang.jl` offers more of an offline code generation approach. Similarly to `CBinding.jl`, it uses the Clang frontend to parse C headers and generate Julia bindings. However, instead of incorporating this process into the user's runtime, it gives you a tool that can be used to pregenerate the bindings in a separate step. 

Typically, the workflow involves preparing a `generator.jl` script and accompanying `generator.toml` configuration file. This allows you to modify the output during the generation. You can skip unwanted symbols or rewrite the symbol names before printing the final bindings. The output is a Julia code that exposes all the bindings that can be included in user's codebase without further need of the `Clang.jl` library. #cite(<c_clangjl_github>) 

=== `Cxx.jl`

// https://github.com/JuliaInterop/Cxx.jl
`Cxx.jl` is in some sense the closest #cpp analogue to the native approach described so far. Like `@ccall`, it lets Julia code drive foreign code directly from the Julia side, but instead of targeting only C-compatible symbols in a shared library it aims to expose #cpp more directly. Its central interface is the `@cxx` macro, which allows Julia code to call #cpp functions and methods directly.

Companion constructs such as `cxx"""..."""` and `icxx"""..."""` can even embed #cpp declarations or statements directly in Julia code. This makes the library attractive for quick experiments because it feels like an extension of Julia's native foreign-function interface from C to #cpp. In principle, this could allow a Julia user to load TNL headers and shared libraries and drive selected parts of the API from Julia without first building a dedicated wrapper package. #cite(<c_cxxjl>)

Unlike `Clang.jl`, however, `Cxx.jl` is not just a binding generator. Its implementation uses Clang together with Julia's staged functions and `llvmcall` machinery to build and fully compile #cpp expressions on demand.  This direct reliance upon Clang sadly also means it cannot be easily swapped for `nvcc` and using TNL code would likely face additional challenges. #cite(<c_cxxjl_impl>)

Most importantly, the library is currently archived and unmaintained. The package only works out of the box with older Julia versions (1.1.x to 1.3.x). This makes it unsuitable for a new jTNL project. Instead, the authors recommend using `CxxWrap.jl` which approaches the bindings differently and as a result is much more stable. 

=== `CxxWrap.jl`

// https://github.com/JuliaInterop/CxxWrap.jl
`CxxWrap.jl` takes almost the opposite approach. Instead of injecting #cpp directly into the Julia session, it asks the binding author to write an explicit wrapper layer in #cpp, compile it into a shared library, and then load that library from Julia using the `@wrapmodule` macro. The project describes itself as a Boost.Python-like solution for Julia, and in this sense it is laso much closer to nanobind used by PyTNL. The binding logic stays on the native side, while Julia only consumes the resulting module. Under the hood, the package relies on the companion `libcxxwrap-julia` library, which provides the native registration API and the build integration needed by downstream wrappers. #mcite(<c_cxxwrapjl>, <c_libcxxwrap_julia>)

This is important for TNL because it matches the structure of the existing codebase far better than a C-only compatibility layer. `CxxWrap.jl` supports ordinary functions, member functions, lambdas, classes with single inheritance, smart pointers, tuples, enums, and a range of STL containers. Most importantly, it also supports template classes by mapping them to Julia parametric types. Although the limitation is that only those template instantiations explicitly listed in the wrapper are available. For jTNL, this means that `CxxWrap.jl` would not eliminate the need to preselect combinations of scalar types, dimensions, or devices, but it would provide a fairly natural way to present those selected instantiations in Julia syntax. #cite(<c_cxxwrapjl>)

For higher-order functions, `CxxWrap.jl` is particularly interesting because it also directly supports passing callbacks from Julia into #cpp. The more dynamic and natural way is using `jlcxx::JuliaFunction` wrapper. It can either directly get a Julia function by it's name or be constructed from a `jl_function_t` pointer obtained from a function argument. That however once again internally boxes the arguments and return values which introduces overhead on each call.

The more low-level way is using `@safe_cfunction` to create a C-compatible function pointer from a Julia function and pass it into #cpp. Less convenient but the call overhead should not be larger then calling a regular C function through its pointer. This approach closely resembles the Numba `@cfunc` approach on the Python side and could likely mirror it's performance as well.

Overall, `CxxWrap.jl` appears to be the most realistic foundation for an initial jTNL implementation. Unlike `Cxx.jl`, it is maintained and aligned with current Julia packaging practices. And compared to `CBinding.jl` or `Clang.jl`, it does not require reducing TNL to a separate C API before any useful bindings can be built. In many ways, the project would be quite similar to the existent PyTNL bindings. The syntax on the binding side would likely be familiar to anyone already working on PyTNL and handling the user-defined code on the Julia side faces similar challenges as the Python side. The main difference is that Julia already natively supports the JIT compilation and no third-party tools like Numba are needed to achieve good performance.

// TODO: mention ho CUDA.jl could be used for kernels?

== Binding the PyTNL 

Building a jTNL package from scratch is going to be a significant undertaking, even with all the lessons learned from the PyTNL development. A much quicker way to expose TNL functionality in Julia could be to wrap the already existing PyTNL package instead of directly binding the C++ core. 

=== `PythonCall.jl`

// https://juliapy.github.io/PythonCall.jl/v0.9/
PythonCall.jl is a modern Julia library designed for seamless, two-way interoperability between Julia and Python. It handles the automatic conversion of basic types, can wrap Python objects in native-feeling Julia types, even allows fast non-copy sharing of NumPy NDArrays between the two languages. Most importantly, the whole process happens at runtime. Julia user can run any Python code, be it through prepared functions or even executing arbitrary strings of Python code with `@pyexec` macro, without needing to pre-generate any bindings. #cite(<c_pythoncall_docs>)

Of course, the price for such flexibility is rather steep. All the python code is executed through normal Python interpreter which is installed along the library as a dependency. All limitations currently inherent to PyTNL would still apply, with the additional overhead of one more language boundary crossing for all calls. 

Any use cases requiring native performance would likely be completely out of reach. For a quick prototyping in Julia however, PythonCall can essentially be used to run TNL code right away without any support from (Py)TNL developers.


// === BinaryBuilder.jl

// // https://docs.binarybuilder.org/stable/
// // TODO: explore how BinaryBuilder.jl could be used for code generation using nvcc compiler
// // TODO: explore if it could help expose custom user defined code that would extend the TNL
// BinaryBuilder is not a good tool for runtime compilations... it's somethign like goreleaser, meant for pipelines... SKIPPED
