#import "ctufit-thesis.typ": *

= Julia TNL bindings

// https://docs.julialang.org/en/v1/
Julia programming language is a flexible dynamic language with performance comparable to traditional statically typed languages like #cpp. To achieve good performance, Julia relies on type inference and just-in-time compilation using the LLVM framework. What's more, among languages advantages authors of Julia list "No need to vectorize code for performance; devectorized code is fast", "Designed for parallelism and distributed computation", "Powerful shell-like capabilities for managing other processes" or even "Call C functions directly (no wrappers or special APIs needed)". #mcite(<c_julia_siam_article>, <c_julia_docs>)

All these features all make Julia a very attractive candidate for new TNL frontend and might even sidestep some of the challenges encountered in PyTNL. The native JIT compilation options should make it possible to write user-defined functions directly in Julia and still achieve good performance, without the need for a separate third-party tool like Numba. 

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

Building a jTNL package only around these native capabilities however would be a rather limiting. The `@ccall` macro is designed specifically for C APIs, so it cannot directly expose #cpp classes, templates or overloaded methods. Building jTNL would therefore require a C compatibility layer around only selected TNL functionality.

A more promising approach would therefore be using some of the existing Julia libraries for #cpp binding that could expose the TNLs API more directly.

== Bindings libraries

Three Julia packages are particularly relevant when considering how such a wrapper could be initialized.

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
// TODO: explore the @cxx macro
// TODO: explain that it is archived and only supports older Julia versions
// TODO: explain that cause of that it is not a realistic usage for jTNL

=== `CxxWrap.jl`

// https://github.com/JuliaInterop/CxxWrap.jl
// TODO: explore how it differes from just @ccall and @cxx macros. How it is more similar to nanobind and other python binding libraries. 
// TODO: explore how it handles templates
// TODO: explore how it handles function arguments, and higher order functions (callbacks)
// 


== Other approaches

=== BinaryBuilder.jl

// https://docs.binarybuilder.org/stable/
// TODO: explore how BinaryBuilder.jl could be used for code generation using nvcc compiler
// TODO: explore if it could help expose custom user defined code that would extend the TNL


=== PythonCall

// https://juliapy.github.io/PythonCall.jl/stable/pythoncall/
// TODO: explore if binding PyTNL instead of TNL could speed up the developement of Julia interface
// TODO: explore the downsides