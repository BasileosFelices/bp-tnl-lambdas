#import "ctufit-thesis.typ": *
#let cpp = box[C#h(-0.1em)++\u{2060}]

= Higher order functions and just-in-time compilation

This chapter introduces higher-order functions in TNL and explores Python binding strategies for them. It also discusses the use of just-in-time compilation techniques to improve the performance of Python callbacks that would allow them to reach the native performance of the original #cpp code.

== Higher-order functions in TNL

// https://tnl-project.gitlab.io/tnl/classTNL_1_1Containers_1_1Array.html#aab46e9d7161d32fd887683f2d2c52046
TNL utilizes higher-order functions and methods quite extensively to allow users to express their custom logic. The TNL arrays have the `.forElements` and `.forAllElements` methods that allow running any custom element-wise operations on the elements. These methods take a lambda function that takes an index and a reference to the current element. The lambda is then called for each element of the array or each element inside given bounds. This is performed at the same place where the array is allocated. That is, it allow parallel execution of the GPU provided the lambda is declared `__cuda_callable__`.

#code1([Example of `.forElements` TNL Array method as showcased in the documentation], <tnl_array_forelements_code_example>, 
```cpp
   const int size = 10;
   Containers::Array< float, Device > a( size );
   Containers::Array< float, Device > b( size );
   b = 0;
 
   // Initiate the elements of array `a`
   a.forAllElements(
      [] __cuda_callable__( int i, float& value )
      {
         value = i;
      } );
 
   // Initiate elements of array `b` with indexes 0-4 using `a_view`
   auto a_view = a.getView();
   b.forElements( 0,
                  5,
                  [ = ] __cuda_callable__( int i, float& value )
                  {
                     value = a_view[ i ] + 4.0;
                  } );
```
)

Another example could be the `parallelFor` function from the Algorithms namespace. As the name suggests, it handles execution of generic loops in a parallel way. Accepting an index range and a lambda function with further optional arguments. Interestingly, it even supports 2D and 3D multi-index. Allowing users to, for example, easily setup the data as shown in the code snippet below.

#code1([Example of `parallelFor` function as showcased in the documentation], <tnl_array_parallelfor_code_example>, 
```cpp
   const int xSize = 10;
   const int ySize = 10;
   const int zSize = 10;
   const int size = xSize * ySize * zSize;
   Vector< double, Devices::Cuda > v( size );

   auto view = v.getView();
   auto init = [ = ] __cuda_callable__( const StaticArray< 3, int >& i ) mutable
   {
      view[ ( i.z() * ySize + i.y() ) * xSize + i.x() ] = c;
   };
   StaticArray< 3, int > begin{ 0, 0, 0 };
   StaticArray< 3, int > end{ xSize, ySize, zSize };
   parallelFor< Device >( begin, end, init );
```
)

// https://en.cppreference.com/cpp/utility/functional/function
The `parallelFor` gets a lot of use and flexibility thanks to context capturing ability of #cpp lambda functions. Lambda functions, especially those introduced with #cpp 11 standard, are not merely anonymous pieces of code. When a lambda refers to variables from the surrounding scope, the compiler generates a small callable object, often called a closure, that stores the captured data together with the function body. The data may be captured by value, meaning a copy is stored inside the closure, or by reference, meaning the closure keeps access to an existing object. In practice, this means that the lambda can behave as a compact custom function that already carries its own local state.

This is particularly useful for higher-order interfaces such as `parallelFor`. The algorithm itself only needs to know how to iterate over a range of indices and when to invoke the callback. Any additional information, such as views of arrays, scalar parameters, material constants, or auxiliary buffers, can be supplied through the lambda capture instead of being threaded through the algorithm interface explicitly. The resulting API remains generic and reusable, while the user code remains local, readable, and close to the point where the data are prepared.

This ability to combine executable logic with state prepared in the surrounding scope is one of the main reasons why lambda-based higher-order interfaces are so practical in modern #cpp.

== PyTNL and Nanobind

// https://nanobind.readthedocs.io/en/latest/functions.html#higher-order-functions
// https://nanobind.readthedocs.io/en/latest/exchanging.html

Nanobind supports higher-order functions, but it does so using Python interoperability mechanisms rather than by turning Python lambdas into native #cpp closures. For PyTNL, the two relevant approaches are type casting through `std::function` and direct manipulation of Python callables through wrapper types such as `nb::callable` or the more general `nb::object`.

The most convenient binding strategy is to expose a #cpp function that accepts a `std::function<R(Args...)>`. After including `nanobind/stl/function.h`, nanobind can accept any Python callable with a compatible signature, including ordinary functions, callable objects, and lambda expressions. This is the mechanism shown in the nanobind documentation for higher-order functions. From the Python side, the user simply passes a lambda as an argument, while from the #cpp side the callback is received through the familiar `std::function` interface. This is useful as it allows usage of already existing higher-order functions in TNL without modification.

#code1([Example of a bound method accepting native `std::function`. `DoubleVector` represents custom class wrapping access to `std::vector<Double>`.], <nanobind_std_function_binding_example>,
```cpp
#include <nanobind/nanobind.h>
#include <nanobind/stl/function.h> // Required for std::function conversion
#include <functional>

namespace nb = nanobind;

NB_MODULE(my_module, m) {
    nb::class_<DoubleVector>(m, "DoubleVector")
        ... // Other bindings for DoubleVector
        .def("forAll_stdfunc", 
            // the actual implementation accepts and uses directly native std::function
            [](DoubleVector &self, const std::function<double(double)>& f) {
                for (double &x : self.data) {
                    x = f(x);
                }
            }, nb::arg("f"),
            "Call f(x) for every element x using a std::function wrapper."
        );
}
```
)

Python function passed trough the interface even keep the full flexibility of Python callables, including the ability to capture context. The code snippet below (@nanobind_std_function_capture_example) shows how even object bound by nanobind in the first place can be captured by the Python lambda and used in the callback.

#code1([Example of a Python lambda with context capture passed through nanobind. Assertion passes.], <nanobind_std_function_capture_example>,
```python
vector = bpcode.DoubleVector([0.0] * 6)

# vector is captured by the closure; the C++ loop calls f(i) with no extra args
bpcode.sequentialFor_callable(0, 6, lambda i: vector.__setitem__(i, float(i * i)))
assert vector == [0.0, 1.0, 4.0, 9.0, 16.0, 25.0]
```)

This convenience, however, only obscures what happens under the hood. The Python lambda remains a Python object, including its Python closure state. Nanobind stores a reference to that callable and constructs a callable #cpp adapter around it. Whenever the #cpp code invokes the callback, nanobind must convert the input arguments to Python objects, call the Python function while holding the interpreter state (and the GIL), and then convert the result back to the requested #cpp type. In other words, the code remains a Python callback and is still always executed through the Python interpreter.  

The alternative is to accept the callback explicitly as `nb::callable` or `nb::object`. This corresponds to nanobind's wrapper-based exchange model. In that case, the bound function does not ask nanobind to turn the Python callable into an ordinary #cpp function object. The difference between the two is mainly in safety, with `nb::callable`, nanobind checks immediately at the language boundary whether the object is indeed callable. With `nb::object`, any Python object passes and an error will only likely occur when the object is actually invoked. Compared to the #cpp `std::function` adapter, both of these approaches make it more explicit that the callback is still a Python object and that the execution will still go through the interpreter. They also allow more flexibility in terms of what kind of Python callables can be passed, as they do not require a specific signature or return type.

#code1([Example of a accepting Python objects directly as `nb::callable` or `nb::object`. `DoubleVector` represents custom class wrapping access to `std::vector<Double>`.], <nanobind_std_callable_binding_example>,
```cpp
#include <nanobind/nanobind.h>

namespace nb = nanobind;

NB_MODULE(my_module, m) {
    nb::class_<DoubleVector>(m, "DoubleVector")
        ...         
        .def("forAll_callable",
            [](DoubleVector &self, nb::callable f) {
                for (double &x : self.data) {
                    // nb::cast is used to convert the Python return value back to double
                    x = nb::cast<double>(f(x));
                }
            }, nb::arg("f"),
            "Call f(x) for every element x using nb::callable.")
        .def("forAll_object",
            [](DoubleVector &self, nb::object f) {
                for (double &x : self.data) {
                    x = nb::cast<double>(f(x));
                }
            }, nb::arg("f"),
            "Call f(x) for every element x using a raw nb::object.");
}
```
)

Of the three, using `nb::object` as the callback likely invokes the least amount of nanobind overhead. That said, the fundamental cost model remains the same across all three approaches. The callback is still a Python object and the main cost of crossing the language boundary, that is, converting arguments, waiting on the Python interpreter and GIL, and converting the results back, is still paid each time the callback is invoked.

This understanding is crucial for TNL. Native TNL higher-order functions are designed for very fine-grained callbacks, often one call per element, and in the CUDA case they may also need to be compiled into device code. A native #cpp lambda works well in this environment because its type, capture layout, and callable body are all known to the compiler. A Python lambda passed through nanobind does not have these properties. Its captured state lives in Python objects, its body is not available to the #cpp compiler, and it cannot be inlined into templated TNL kernels or compiled as `__cuda_callable__` device code. It fundamentally cannot be as the PyTNL module compilation happens way before any user code is executed. Nanobind therefore makes the interface look similar, but not equivalent in implementation.

For PyTNL this means that nanobind on its own is perfectly capable of exposing callback-based APIs that accept Python lambdas, but such callbacks are best viewed as interoperability features, not as a path to native-performance generic programming. They are suitable when convenience is more important than throughput, or when the callback is invoked only occasionally. They are much less suitable for element-wise loops over large arrays, where the interpreter and conversion overhead is paid for every single element.

=== Obstacles to native performance

The main obstacles to native performance can be summarized as follows:

- *Initial bound-call overhead.* Calling the exposed PyTNL method from Python still goes through nanobind's ordinary function-binding machinery. This cost is paid once per top-level call and is usually not the dominant problem in the present use case.
- *Repeated callback dispatch.* Once inside the bound method, every invocation of the Python callback still passes through a nanobind/Python adapter path. For TNL-style element-wise execution this repeated dispatch is paid once per element and accumulates quickly.
- *Argument and return-value conversion.* Each callback invocation crosses the Python-#cpp boundary in both directions. Input values must be boxed into Python objects and the result must be converted back to a native #cpp type.
- *Interpreter execution.* The callback body is still executed as Python code from the point of view of the binding layer. Nanobind makes passing the callback convenient, but it does not make the callback itself native machine code.
- *GIL constraints.* Entering Python requires interpreter coordination and typically holding the global interpreter lock. This limits parallel execution and makes Python callbacks a poor match for the highly parallel execution model expected by TNL.
- *No compiler visibility into the callback.* The #cpp compiler cannot see the callback body or its captured state, so it cannot inline it, optimize around it, or treat it as an ordinary compile-time callable in templated code.
- *No device-code path.* A Python callback cannot be compiled as `__cuda_callable__` code and cannot be embedded directly into CUDA kernels. This prevents it from serving as a true substitute for native TNL lambdas on the GPU.

Since the potential benefits of making this work are substantial, the following sections explore whether at least some of these constraints could be eliminated. Namely, just-in-time (JIT) compilation and runtime compilation techniques could potentially completely eliminate the interpreter execution overhead. And CUDA device runtime compilation could even allow the callback to be executed on the GPU. 

// too soon to mention, will be discussed after the numba, nvrtc sections
// This also explains why merely decorating the Python callback with a JIT compiler such as Numba does not by itself solve the problem. If the resulting callable is still passed into #cpp as `nb::callable`, `nb::object`, or `std::function`, nanobind still sees it primarily as a Python callable and dispatches through the same callback machinery. The overhead of repeatedly re-entering Python remains. To achieve native performance, the execution model itself must change so that the computation no longer crosses the Python-#cpp boundary once per element.

== Numba <numba_introduction>

// https://numba.readthedocs.io/en/0.65.0/
Numba is a just-in-time compiler for Python focused primarily on numerical code. Instead of interpreting the decorated function statement by statement, Numba analyzes its bytecode together with the concrete argument types seen at runtime and generates specialized native machine code by leveraging the LLVM compiler infrastructure. In the common case of loop-heavy numerical kernels over arrays, this can remove a large part of the overhead normally associated with Python execution while preserving the convenience of writing the logic in Python syntax.

Among the available Python acceleration tools, Numba was a particularly relevant starting point for this work. The aim was not to replace PyTNL with a separate numerical framework, but to extend it with a compilation layer for user-defined logic. Libraries such as JAX or CuPy are powerful, but they are centered around their own array objects and execution models, making them closer to alternative numerical environments than to lightweight extensions of an existing library. At the other end of the spectrum, tools such as Cython or Pythran can generate highly efficient native code, but they are oriented more toward source translation and extension-module builds than toward compiling ordinary user-defined Python functions dynamically at runtime. Numba occupies a pragmatic middle ground: it is well established in the scientific Python ecosystem, works naturally with array-oriented numerical code, supports both CPU and CUDA execution, interoperates with standard memory-sharing protocols, and uniquely offers both ordinary JIT-compiled Python functions and native C-callable callbacks through `@cfunc`.

In the context of this thesis, this makes Numba an attractive first candidate for narrowing the gap between convenient Python user code and native TNL execution. The central hope was straightforward: if the user-defined callback or kernel could be compiled ahead of its actual execution, then the repeated cost of interpreting Python code in the innermost loop could disappear, and the resulting performance could approach that of an equivalent native #cpp implementation. At this stage, Numba therefore appears to offer exactly the kind of bridge that PyTNL needs --- Python as the authoring language, but native code as the execution vehicle.

There are, however, several different ways in which Numba can compile a function, and they are not equivalent from the point of view of PyTNL integration. For the purposes of this chapter, the most relevant options are the ordinary function decorators `@jit` and `@njit`, which compile Python functions for efficient execution from Python, and `@cfunc`, which produces a native C-callable function pointer. Numba also provides higher-level decorators such as `@vectorize`, but those are more relevant for whole-array operations through the transfer protocols introduced in the next chapter and are therefore postponed there.

// TODO: FINISH REVIEW FROM HERE

=== Numba `@jit` and `@njit`

The standard entry point to Numba is the `@jit` decorator. It marks a Python function for compilation and, in its most common form, defers the actual compilation until the first call. At that moment, Numba observes the argument types, builds a matching specialization, and reuses it for later calls with the same type combination. This makes it possible to write an ordinary Python function with loops, indexing, scalar arithmetic, and selected NumPy operations, and then have that function execute as compiled machine code instead of being interpreted repeatedly.

For performance-oriented use, the most important mode is Numba's so-called nopython mode. In this mode, the compiled region operates entirely on native values and no longer relies on the Python interpreter while running. The `@njit` decorator is the conventional spelling for this usage and corresponds to `@jit(nopython=True)`. For this thesis, `@jit`/`@njit` were the most natural first experiment because they preserve the most ergonomic programming model: the user still writes a normal Python function and can invoke it from Python almost as usual, while hoping that the hot loop itself will run at native speed.

This makes `@jit` and `@njit` particularly suitable for the scenario where the user supplies a whole-array routine rather than a per-element callback. If PyTNL data can be exposed through a standard memory interchange mechanism, Numba can compile a function that iterates over that memory directly. In such a design, the interpreter would be crossed only to enter the compiled function, not once per processed element. That is a fundamentally more promising execution model than repeatedly invoking a Python callable from inside a native TNL loop.

// TODO: Insert prepared `@jit` / `@njit` example showing a loop-heavy Python function and note whether you want to use `@jit` explicitly or present `@njit` as the preferred spelling from the outset.

=== Numba `@cfunc`

The `@cfunc` decorator serves a different purpose. Instead of producing a Python-callable function that happens to execute compiled code internally, it generates a native callback with an explicit C-compatible signature. The signature must be specified up front, and the resulting object exposes both a callable wrapper and, more importantly for interoperability, the address of the compiled function. This makes `@cfunc` interesting precisely in situations where a foreign library expects a raw function pointer rather than a Python object.

From the perspective of PyTNL higher-order functions, this looks much closer to the native #cpp callback model. If a bound function can be adapted to accept a function pointer with a matching signature, then the callback no longer needs to be re-entered through Python on every invocation. In principle, this eliminates exactly the repeated interpreter dispatch that made nanobind-based Python callbacks unsuitable for fine-grained element-wise execution.

The trade-off is that `@cfunc` is also much more restrictive. The callable must follow an explicitly declared low-level signature, and any state that would normally be captured by a Python closure has to be represented in some more explicit form. In other words, `@cfunc` offers a path that is potentially much closer to native callback performance, but it does so by moving away from the full flexibility of ordinary Python callables. That trade-off is central to the evaluation later in this chapter.

// TODO: Insert prepared `@cfunc` example together with the exact callback signature used by the PyTNL benchmark bindings.


=== Numba CUDA

// https://nvidia.github.io/numba-cuda/
// TODO: review and rewrite, too aggressive imo
For GPU execution, Numba also provides a CUDA backend, commonly referred to as Numba-CUDA. Rather than compiling ordinary numerical Python functions for CPU execution, this backend compiles a restricted subset of Python into CUDA kernels and device functions that follow the CUDA execution model. This makes it possible to write GPU kernels in Python syntax, but it also means that the resulting object is fundamentally different from the CPU-side functions discussed above.

That difference is crucial for this thesis. With CPU Numba, the `@jit` decorator still produces a Python-callable object, and `@cfunc` can produce a host-side function pointer with a conventional scalar signature. A kernel produced by `@cuda.jit` is neither of these. It is a kernel launch object that must be invoked with an explicit grid configuration, and it does not behave like a scalar callback of the form `f(x) -> double`. CUDA kernels also do not return scalar values in the ordinary function sense. Instead, they are launched by host code and write their results into arrays residing in device memory.

#code1(
  [A minimal Numba-CUDA kernel launched over a CuPy array. The key difference from CPU Numba is the launch syntax `kernel[blocks, threads](...)` and the fact that the kernel updates device memory instead of returning element values.],
  <numba_cuda_kernel_launch_example>,
  ```python
  import cupy as cp
  from numba import cuda

  @cuda.jit
  def scale_kernel(data, scale):
      i = cuda.grid(1)
      if i < data.size:
          data[i] = data[i] * scale

  data = cp.ones(1024, dtype=cp.float64)
  threads = 256
  blocks = (data.size + threads - 1) // threads
  scale_kernel[blocks, threads](data, 2.0)
  ```
)

This is already enough to show why the previous callback-based approach does not carry over to the GPU. The kernel is not something that can be passed through `mapAll` or a similar higher-order binding as if it were just another callable. It requires launch parameters, executes many threads at once, and expresses its results through writes to device arrays rather than through a scalar return value. In other words, the CUDA execution model changes not only how the function is compiled, but also what kind of interface it can meaningfully satisfy.

If a GPU-backed container is to interoperate with Numba-CUDA realistically, the correct analogue is therefore not passing a kernel through the existing callback interface, but sharing the underlying GPU memory and launching the kernel over that memory from Python. In practice, this means exposing a device-memory interchange mechanism such as the CUDA Array Interface rather than the ordinary CPU buffer protocol. Once the container exports its device allocation in such a form, Numba-CUDA can consume it without a copy and launch a kernel directly over the shared memory. This is the closest GPU counterpart to the CPU-side `@jit` approach, but an important difference remains: the launch itself stays on the Python side instead of being embedded into the existing native higher-order function interface.

== NVRTC <nvrtc_introduction>

== Benchmark <function_calling_from_cpp_benchmark>

#figure(
  table(
    columns: (1fr, auto, auto, auto, auto),
    align: (left, left, left, right, right),
    inset: (x: 8pt, y: 10pt),
    table.header([*Method*], [*Binding*], [*Callback*], [*Avg \ (ms/iter)*], [*vs baseline*]),
    [Python list], [—], [—], [82.589], [(baseline)],
    [Python `DoubleVector`], [—], [—], [237.579], [2.9× slower],
    [NumPy `*= 2.0`], [—], [—], [0.757], [109.1× faster],
    [C++ `multiplyAll`], [—], [—], [1.222], [67.6× faster],
    [`mapAll`], [`nb::object`], [Python λ], [167.431], [2.0× slower],
    [`mapAll`], [`nb::callable`], [Python λ], [169.207], [2.0× slower],
    [`mapAll`], [`nb::callable`], [`@jit`], [379.349], [4.6× slower],
    [`mapAll`], [`std::function`], [`@jit`], [402.222], [4.9× slower],
    [`forAll`], [fn ptr], [`@cfunc`], [10.584], [7.8× faster],
    [`seqFor`], [fn ptr], [`@cfunc`], [5.356], [15.4× faster],
    table.hline(stroke: 1.5pt),
  ),
  caption: [
    Scenario A --- element-wise multiply (`vec[i] *= 2.0`), $N = 2^(21) = 2 thin 097 thin 152$
    sorted by calling strategy. Baseline is plain Python list iteration.
    Benchmark ran on a PC with Ryzen 3600 CPU in WSL2 environment.
  ],
) <benchmark_scenario_a_table>

#figure(
  table(
    columns: (1fr, auto, auto, auto, auto),
    align: (left, left, left, right, right),
    inset: (x: 8pt, y: 10pt),
    table.header([*Method*], [*Binding*], [*Callback*], [*Avg \ (ms/iter)*], [*vs baseline*]),
    [Python list], [—], [Python fn], [475.667], [(baseline)],
    [Python list], [—], [`@jit` fn], [346.476], [1.4× faster],
    [Python `DoubleVector`], [—], [—], [743.670], [1.6× slower],
    [NumPy vectorized], [—], [—], [59.106], [8.0× faster],
    [C++ `heavyComputeAll`], [—], [—], [34.620], [13.7× faster],
    [`mapAll`], [`nb::object`], [Python fn], [567.003], [1.2× slower],
    [`mapAll`], [`nb::callable`], [Python fn], [566.121], [1.2× slower],
    [`mapAll`], [`nb::callable`], [`@jit` fn], [312.681], [1.5× faster],
    [`mapAll`], [`std::function`], [`@jit` fn], [339.663], [1.4× faster],
    [`forAll`], [fn ptr], [`@cfunc`], [35.144], [13.5× faster],
    [`seqFor`], [fn ptr], [`@cfunc`], [34.775], [13.7× faster],
    table.hline(stroke: 1.5pt),
  ),
  caption: [
    Scenario B --- heavier element-wise compute ($sin(x) + cos(x) dot sqrt(|x|+1)$), $N = 2^(21) = 2 thin 097 thin 152$
    sorted by calling strategy. Baseline is plain Python list with a Python function.
    Benchmark ran on a PC with Ryzen 3600 CPU in WSL2 environment.
  ],
) <benchmark_scenario_b_table>

== Other Python libraries

=== CuPy

=== Polars

// https://docs.pola.rs/user-guide/expressions/user-defined-python-functions/#processing-a-whole-series-with-map_batches

=== NumPy

// TODO: mention inspiration from some libraries described above?
=== JAX