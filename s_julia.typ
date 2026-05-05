#import "ctufit-thesis.typ": *

= Julia TNL bindings

// https://docs.julialang.org/en/v1/
Julia programming language is a dynamic language that aims to combine high-level expressiveness with performance comparable to traditional statically typed languages such as #cpp. To achieve this, Julia relies on type inference and just-in-time compilation using the LLVM framework. Among the language advantages highlighted by the Julia authors are the claims that there is no need to vectorize code to obtain good performance, that the language is designed for parallel and distributed computation, and that it can call C functions directly. #mcite(<c_julia_siam_article>, <c_julia_docs>)

These properties make Julia an interesting candidate for a future TNL frontend. In particular, Julia's native compilation model suggests that some of the difficulties encountered in PyTNL, especially around integrating user-defined code efficiently, may be less severe in a Julia-based design. At the same time, no jTNL package existed prior to this work and such a package could not be implemented within the scope of this thesis.

This chapter therefore does not present an implemented binding layer. Its goal is instead to compare technically plausible strategies for exposing TNL in Julia, identify their main constraints, and narrow the design space to the options that appear most realistic for future work.

== Aim and evaluation criteria

The central question of this chapter is not whether Julia can interoperate with native code in general, but which integration strategy appears most compatible with the specific requirements of TNL. These requirements follow directly from the earlier discussion of PyTNL and TNL itself.

In particular, a useful jTNL design should:

+ minimize the need to flatten TNL into a separate C API,
+ preserve enough of the original #cpp type structure to expose selected classes and templates in a natural way,
+ provide a plausible path for passing user-defined functions into native code,
+ fit the existing wrapper-oriented architecture already explored in PyTNL,
+ remain compatible with a codebase that targets both CPU and CUDA backends,
+ and rely on tooling whose maintenance status and build complexity make it a realistic basis for a new project.

The comparison in this chapter is therefore qualitative. It is based on the documented capabilities of the surveyed libraries, their maintenance status, and their apparent architectural fit with the requirements of TNL. In this sense, the chapter aims to identify which directions appear promising enough to justify future implementation work.

== Native capabilities

// https://docs.julialang.org/en/v1/manual/calling-c-and-fortran-code/
Julia already provides strong native interoperability primitives for C and Fortran. These primitives are relevant because they establish the baseline capabilities available without any third-party binding library.

The basic mechanism for calling native functions is the `@ccall` macro, which can invoke symbols from shared libraries directly and wrap them in an ordinary Julia function.

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

Julia also exposes the `@cfunction` macro, which can produce a C-compatible function pointer from a Julia function. Together with `@ccall`, this makes it possible to express callback-based C interfaces directly from Julia.

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
```
)

These examples demonstrate that Julia already provides direct support for calling C functions and creating C-compatible callbacks. For TNL, this is encouraging because it suggests that a callback interface simpler than the Python one discussed in @pytnl_nanobind_callbacks may be plausible.

At the same time, building jTNL solely around the native Julia FFI would be restrictive. The `@ccall` interface is designed for C APIs, not for exposing #cpp classes, templates, namespaces, or overloaded methods directly. A TNL interface built only on top of these native primitives would therefore require a dedicated C compatibility layer in front of selected parts of the library. Such a layer might still be useful in limited cases, but it would necessarily hide a large part of TNL's native type structure.

== Candidate integration strategies

The candidate approaches can be divided into three broad groups. The first group keeps Julia on the C side of the boundary and assumes that TNL would first be reduced to a dedicated C API. The second group attempts to expose #cpp more directly. The third group does not bind TNL itself, but instead reuses the already existing PyTNL layer from Julia.

=== C-oriented strategies

The advantage of C-oriented tools is that they build on Julia's strongest and most stable interoperability path. Their main drawback is structural: to use them for TNL, a separate C-facing compatibility layer would first need to be designed, implemented, and maintained. That would increase the amount of native wrapper code and would also flatten much of the type information that makes TNL expressive on the #cpp side.

==== `CBinding.jl`

// https://github.com/analytech-solutions/CBinding.jl
`CBinding.jl` automates generation of Julia bindings from C headers or C declarations embedded directly in Julia code. Instead of writing every `@ccall` signature manually, the library uses Clang for parsing and translation and then exposes the resulting types and functions through convenient Julia syntax such as the `c"..."` macro. #cite(<c_cbinding_github>)

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
```
)

For a C library, this can substantially reduce wrapper boilerplate and simplify maintenance because the bindings can be regenerated when the C interface changes. For TNL, however, the key limitation remains unchanged: `CBinding.jl` would only become useful after a separate C API had already been designed. It therefore appears more suitable for wrapping a deliberately restricted compatibility layer than for exposing TNL's native #cpp interface directly.

One practical advantage is that the actual implementation behind such a C API could still be compiled independently as a native library. This means that CUDA-related parts could in principle remain on the native side and continue using an existing build process. That observation makes the approach viable, but not especially attractive, because it solves only the boundary problem and not the loss of TNL's richer type structure.

==== `Clang.jl`

// https://github.com/juliainterop/clang.jl
`Clang.jl` represents a similar strategy, but with more emphasis on offline code generation. It uses the Clang frontend to parse C headers and generate Julia wrapper code in a separate preprocessing step. The typical workflow uses a `generator.jl` script and a `generator.toml` configuration file, allowing the generated output to be filtered or renamed before it is committed into the package source. #cite(<c_clangjl_github>)

Compared to `CBinding.jl`, this can make the resulting Julia package cleaner because the end user does not need to carry the translation machinery at runtime. For TNL, however, the strategic limitation is the same. `Clang.jl` would be useful only after a C compatibility layer exists, and the main design burden would still lie in deciding which parts of TNL to flatten into that C layer and how much information would be lost in the process.

From the perspective of this thesis, the C-oriented options therefore appear technically feasible but architecturally misaligned. They offer a credible implementation path only if the project deliberately accepts a reduced, C-shaped interface in front of TNL.

=== Direct #cpp strategies

The second group is more attractive conceptually because it attempts to preserve more of the original #cpp structure. This matters for TNL, where templates, overloaded interfaces, and device-specific types are not incidental implementation details but part of the public API.

==== `Cxx.jl`

// https://github.com/JuliaInterop/Cxx.jl
`Cxx.jl` extends Julia with a direct #cpp interface centered around the `@cxx` macro. It allows Julia code to call #cpp functions and methods directly and also provides constructs such as `cxx"""..."""` and `icxx"""..."""` for embedding #cpp declarations or statements in Julia code. #cite(<c_cxxjl>)

In principle, this is appealing because it resembles an extension of Julia's own foreign-function interface from C to #cpp. A user could imagine loading TNL headers and libraries and experimenting with selected parts of the API without first building a separate wrapper package.

For this thesis, however, `Cxx.jl` is not a realistic basis for a new jTNL project. Its implementation depends heavily on Clang, Julia staged functions, and `llvmcall` to build and compile #cpp expressions on demand. #cite(<c_cxxjl_impl>) That architecture may be attractive for interactive exploration, but it appears poorly matched to a codebase whose build depends on conventional compilation workflows and CUDA-related tooling. More importantly, the project is currently archived and only supports substantially older Julia versions. Even if the direct #cpp model is conceptually attractive, its current maintenance state effectively disqualifies it.

==== `CxxWrap.jl`

// https://github.com/JuliaInterop/CxxWrap.jl
`CxxWrap.jl` takes almost the opposite approach. Instead of injecting #cpp directly into the Julia session, it asks the binding author to write an explicit wrapper layer in #cpp, compile it into a shared library, and load that library from Julia using the `@wrapmodule` macro. The project describes itself as a Boost.Python-like solution for Julia and in this sense it is also structurally closer to nanobind used by PyTNL. The binding logic stays on the native side, while Julia consumes a prepared module through the companion `libcxxwrap-julia` infrastructure. #mcite(<c_cxxwrapjl>, <c_libcxxwrap_julia>)

For TNL, this wrapper-oriented architecture is the main advantage. It preserves a native binding layer where template instantiations, ownership rules, conversions, and device-specific details can be handled explicitly, similarly to PyTNL. `CxxWrap.jl` supports ordinary functions, member functions, classes with single inheritance, smart pointers, enums, tuples, and a range of STL containers. It also supports template classes by mapping selected instantiations to Julia parametric types. #cite(<c_cxxwrapjl>)

This does not remove the need to choose which concrete type combinations should be exported. A future jTNL would still need to decide which scalar types, dimensions, devices, or array specializations to instantiate and expose. Nevertheless, this restriction is already familiar from PyTNL and appears easier to manage than designing custom dispatch model for correct template specialization.

For higher-order functions, `CxxWrap.jl` is particularly interesting because it offers two conceptually different callback paths. The more ergonomic option is `jlcxx::JuliaFunction`, which allows native code to invoke Julia functions obtained either by name or from a Julia function object passed as an argument. This is attractive for convenience, but it also relies on boxing and dynamic conversion of arguments and return values, which faces the already discussed performance limitations.

The lower-level alternative is to use `@safe_cfunction` and pass a C-compatible function pointer into the native layer. This is less convenient, but it appears to be the more plausible approach for callback-heavy or performance-sensitive code. It resembles the `@cfunc`-based path discussed for Python, while avoiding the need for an additional third-party JIT tool analogous to Numba on the Julia side.

These advantages come with a non-trivial engineering cost. A jTNL based on `CxxWrap.jl` would, similarly to PyTNL, require a dedicated native wrapper library. Even so, among the surveyed maintained options it appears to offer the strongest architectural fit for a future jTNL design.

=== Indirect reuse strategy

The final option is not to bind TNL directly at all, but to reuse the already existing PyTNL package from Julia. This does not provide a native Julia frontend in the strict sense, but it may still be a useful short-term path if the main objective is quick experimentation rather than a fully idiomatic binding layer.

==== `PythonCall.jl`

// https://juliapy.github.io/PythonCall.jl/v0.9/
`PythonCall.jl` is a Julia package for two-way interoperability between Julia and Python. It can convert common values automatically, wrap Python objects in Julia-friendly representations, and share NumPy arrays without unnecessary copies in some cases. It also allows Julia code to execute Python code dynamically at runtime. #cite(<c_pythoncall_docs>)

From the perspective of jTNL, this makes `PythonCall.jl` an attractive prototyping tool. A Julia user could access the existing PyTNL functionality almost immediately without waiting for a dedicated Julia wrapper to be developed. This would be especially useful for exploratory scripts, demonstrations, or early interface experiments.

The trade-off is that this route inherits all limitations already present in PyTNL and adds another language boundary on top of them. As a result, it should not be understood as a route to a high-performance or especially idiomatic Julia binding. It is better viewed as a pragmatic reuse strategy for early access and experimentation.

== Recommended direction

The analysis above suggests three different levels of ambition. A C-based approach built with tools such as `CBinding.jl` or `Clang.jl` appears feasible, but only at the cost of designing and maintaining a separate compatibility layer that would flatten a substantial part of TNL's original #cpp interface. Reusing PyTNL through `PythonCall.jl` appears much cheaper initially, but mainly as a prototyping technique rather than as a long-term frontend design.

Among the surveyed options, `CxxWrap.jl` appears to offer the strongest balance between realism and fidelity to TNL's architecture. It retains an explicit native wrapper layer, aligns well with the style of bindings already explored in PyTNL, and seems compatible with exposing selected template instantiations and callback-oriented interfaces without forcing the entire project through a C-only boundary.

For these reasons, `CxxWrap.jl` appears to be the most suitable foundation for any future Julia frontend to TNL. At the same time, `PythonCall.jl` remains a practical option for rapid experimentation.