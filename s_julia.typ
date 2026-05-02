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

// https://github.com/analytech-solutions/CBinding.jl
// https://github.com/JuliaInterop/CxxWrap.jl
// https://github.com/JuliaInterop/Cxx.jl
=== `CBinding.jl`

`CBinding.jl` generates Julia bindings from C headers and C declarations, so it fits best in situations where the original #cpp library can first be reduced to a small and stable C interface. For jTNL, that would mean introducing a handwritten C facade in front of selected TNL components and then exposing only that facade to Julia.

This is attractive as a conservative first step because it keeps the Julia side simple and relies on Julia's strong native support for C interoperability. The drawback is that the difficult part would merely move into the C layer: templates, overloaded methods and much of TNL's richer type structure would already have to be erased before `CBinding.jl` could be used.

=== `CxxWrap.jl`

`CxxWrap.jl` takes a different approach: the wrapper is implemented in #cpp and then loaded into Julia as a native extension. For a project such as jTNL, this is the most natural match because it keeps the binding layer close to the structure of the original library and can expose classes, selected template instantiations, arrays and callback-style interfaces without first collapsing everything into a C API.

Its main cost is that the wrapper layer must be designed explicitly. A jTNL package would still need careful decisions about ownership, memory views, container conversions and which concrete template variants should actually be exported to Julia. Even so, `CxxWrap.jl` appears to be the most realistic foundation for a native jTNL package, because it preserves a direct connection to TNL's abstractions while still allowing the first release to remain intentionally small.

=== `Cxx.jl`

`Cxx.jl` historically offered direct interactive access to #cpp from Julia and was useful for experimentation or quick prototypes. In that sense, it is relevant mainly as a reference point showing that Julia has long attracted interest as a host language for #cpp interoperability.

For a new jTNL package, however, it is not a realistic basis. The project is archived and tied to older Julia versions, so it would introduce maintenance risk from the beginning rather than providing a stable path forward.

Overall, `CxxWrap.jl` seems to be the strongest candidate for a proper native binding layer, while `CBinding.jl` remains a plausible fallback if the immediate priority were a deliberately narrow and low-risk first milestone.


== Recommended initialization

The most pragmatic initialization plan would likely proceed in four steps:

1. Expose only a minimal subset of TNL, preferably host-side arrays, vectors, views and a few representative algorithms.
2. Implement ownership-safe constructors, destructors and metadata queries in a dedicated wrapper layer, rather than trying to mirror the whole C++ API.
3. Adapt the exposed containers to Julia's array conventions so that ordinary Julia code can read and modify their contents naturally.
4. Postpone direct support for higher-order CUDA kernels until the CPU-side data path, ownership model and benchmarks are stable.

This is different from the historical development of PyTNL, where Python packaging, nanobind integration and interoperability protocols had to be solved from the beginning. For jTNL, the first milestone should instead be a narrow but robust native package, and only later a broader, more idiomatic Julian API.


== PythonCall

// https://juliapy.github.io/PythonCall.jl/stable/pythoncall/
PythonCall.jl suggests another possible path: Julia could immediately reuse the already existing PyTNL package through Python interoperability. This would be attractive for rapid prototyping because it avoids blocking on new bindings and makes it possible to validate the user-facing Julia API against an existing implementation. In particular, PythonCall can wrap Python arrays with very low overhead when the Python side exposes the buffer protocol or NumPy-style array interfaces.

This approach would, however, not yet constitute jTNL in the strict sense. The resulting package would still depend on Python, Python package management and, whenever Python objects are manipulated directly, also on the Python runtime constraints such as the GIL. PythonCall is therefore best understood as a migration bridge or prototyping tool, not as the final architecture of a Julia binding layer.


== C like performance

// https://docs.julialang.org/en/v1/manual/performance-tips/
Julia can reach performance close to C or #cpp in hot code, but only under the usual conditions stressed by its documentation: performance-critical code should live inside functions, types should remain concrete, and avoidable allocations or type instability should be eliminated. When these conditions hold, Julia's compiled numerical kernels are a much better match for TNL than ordinary interpreted Python callbacks.

This changes one of the central trade-offs seen in PyTNL. In Python, achieving good performance for user-defined logic required either Numba or a redesign that moved the whole computation away from the repeated Python-#cpp callback boundary. In Julia, once a TNL container is exposed as a Julia array or array-like view, the user can often write the numerical kernel directly in Julia and still obtain compiled native code.

The trade-off is that performance is not automatic. First-call latency remains because methods are compiled on demand, and poorly typed Julia code can easily give up much of the advantage. Still, for CPU-side kernels the overall programming model is cleaner than in Python because the user language and the compiled execution model are already the same language.


== JIT

// https://docs.julialang.org/en/v1/devdocs/jit/
Julia's JIT also changes how the higher-order-function problem should be interpreted. In PyTNL, a large part of the work focused on escaping the cost of repeatedly re-entering the Python interpreter. In Julia, ordinary user functions are already compiled just in time, so element-wise operations over exported host-memory arrays could in principle be written directly in Julia and still achieve good performance.

That said, Julia's JIT does not remove the need for a wrapper around TNL, and it does not automatically solve TNL's most demanding use case: templated #cpp or CUDA kernels that expect compile-time known callables, sometimes even marked `__cuda_callable__`. Passing an arbitrary Julia function into such code is much less straightforward than passing a callback into a plain C API. For this reason, a first version of jTNL would likely focus on data structures, memory views and selected algorithm entry points, while native support for TNL-style higher-order GPU kernels would remain future work.

Overall, Julia appears to be a strong fit for a future TNL frontend, but not because it eliminates the binding work. Its real advantage is that, once the data are made available in Julia, the user no longer needs a second compilation tool comparable to Numba in order to write fast host-side numerical code. The most realistic path would therefore be to start with a small `CxxWrap.jl`-based package, optionally use PythonCall during experimentation, and treat direct integration of templated CUDA higher-order interfaces as a later development stage.