#import "ctufit-thesis.typ": *
#import "@preview/dashy-todo:0.1.3": todo

= Higher order functions and just-in-time compilation

This chapter introduces higher-order functions in TNL and explores Python binding strategies for them. It also discusses the use of just-in-time compilation techniques to improve the performance of Python callbacks that would allow them to reach the native performance of the original #cpp code.

== Higher-order functions in TNL

// https://tnl-project.gitlab.io/tnl/classTNL_1_1Containers_1_1Array.html#aab46e9d7161d32fd887683f2d2c52046
TNL utilizes higher-order functions and methods quite extensively to allow users to express their custom logic. The TNL arrays have the `.forElements` and `.forAllElements` methods that allow running any custom element-wise operations on the elements. These methods take a lambda function that takes an index and a reference to the current element. The lambda is then called for each element of the array or each element inside given bounds. This is performed at the same place where the array is allocated. That is, it allow parallel execution of the GPU provided the lambda is declared `__cuda_callable__`.

#code1(
  [Example of `.forElements` TNL Array method as showcased in the documentation],
  <tnl_array_forelements_code_example>,
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
  ```,
)

Another example could be the `parallelFor` function from the Algorithms namespace. As the name suggests, it handles execution of generic loops in a parallel way. Accepting an index range and a lambda function with further optional arguments. Interestingly, it even supports 2D and 3D multi-index. Allowing users to, for example, easily setup the data as shown in the code snippet below.

#code1(
  [Example of `parallelFor` function as showcased in the documentation],
  <tnl_array_parallelfor_code_example>,
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
  ```,
)

// https://en.cppreference.com/cpp/utility/functional/function
The `parallelFor` gets a lot of use and flexibility thanks to context capturing ability of #cpp lambda functions. Lambda functions, especially those introduced with #cpp 11 standard, are not merely anonymous pieces of code. When a lambda refers to variables from the surrounding scope, the compiler generates a small callable object, often called a closure, that stores the captured data together with the function body. The data may be captured by value, meaning a copy is stored inside the closure, or by reference, meaning the closure keeps access to an existing object. In practice, this means that the lambda can behave as a compact custom function that already carries its own local state.

This is particularly useful for higher-order interfaces such as `parallelFor`. The algorithm itself only needs to know how to iterate over a range of indices and when to invoke the callback. Any additional information, such as views of arrays, scalar parameters, material constants, or auxiliary buffers, can be supplied through the lambda capture instead of being threaded through the algorithm interface explicitly. The resulting API remains generic and reusable, while the user code remains local, readable, and close to the point where the data are prepared.

This ability to combine executable logic with state prepared in the surrounding scope is one of the main reasons why lambda-based higher-order interfaces are so practical in modern #cpp.

== PyTNL and Nanobind <pytnl_nanobind_callbacks>

// https://nanobind.readthedocs.io/en/latest/functions.html#higher-order-functions
// https://nanobind.readthedocs.io/en/latest/exchanging.html

Nanobind supports higher-order functions, but it does so using Python interoperability mechanisms rather than by turning Python lambdas into native #cpp closures. For PyTNL, the two relevant approaches are type casting through `std::function` and direct manipulation of Python callables through wrapper types such as `nb::callable` or the more general `nb::object`.

The most convenient binding strategy is to expose a #cpp function that accepts a `std::function<R(Args...)>`. After including `nanobind/stl/function.h`, nanobind can accept any Python callable with a compatible signature, including ordinary functions, callable objects, and lambda expressions. This is the mechanism shown in the nanobind documentation for higher-order functions. From the Python side, the user simply passes a lambda as an argument, while from the #cpp side the callback is received through the familiar `std::function` interface. This is useful as it allows usage of already existing higher-order functions in TNL without modification.

#code1(
  [Example of a bound method accepting native `std::function`. `DoubleVector` represents custom class wrapping access to `std::vector<Double>`.],
  <nanobind_std_function_binding_example>,
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
  ```,
)

Python function passed trough the interface even keep the full flexibility of Python callables, including the ability to capture context. The code snippet below (@nanobind_std_function_capture_example) shows how even object bound by nanobind in the first place can be captured by the Python lambda and used in the callback.

#code1(
  [Example of a Python lambda with context capture passed through nanobind. Assertion passes.],
  <nanobind_std_function_capture_example>,
  ```python
  vector = bpcode.DoubleVector([0.0] * 6)

  # vector is captured by the closure; the C++ loop calls f(i) with no extra args
  bpcode.sequentialFor_callable(0, 6, lambda i: vector.__setitem__(i, float(i * i)))
  assert vector == [0.0, 1.0, 4.0, 9.0, 16.0, 25.0]
  ```,
)

This convenience, however, only obscures what happens under the hood. The Python lambda remains a Python object, including its Python closure state. Nanobind stores a reference to that callable and constructs a callable #cpp adapter around it. Whenever the #cpp code invokes the callback, nanobind must convert the input arguments to Python objects, call the Python function while holding the interpreter state (and the GIL), and then convert the result back to the requested #cpp type. In other words, the code remains a Python callback and is still always executed through the Python interpreter.

The alternative is to accept the callback explicitly as `nb::callable` or `nb::object`. This corresponds to nanobind's wrapper-based exchange model. In that case, the bound function does not ask nanobind to turn the Python callable into an ordinary #cpp function object. The difference between the two is mainly in safety, with `nb::callable`, nanobind checks immediately at the language boundary whether the object is indeed callable. With `nb::object`, any Python object passes and an error will only likely occur when the object is actually invoked. Compared to the #cpp `std::function` adapter, both of these approaches make it more explicit that the callback is still a Python object and that the execution will still go through the interpreter. They also allow more flexibility in terms of what kind of Python callables can be passed, as they do not require a specific signature or return type.

#code1(
  [Example of a accepting Python objects directly as `nb::callable` or `nb::object`. `DoubleVector` represents custom class wrapping access to `std::vector<Double>`.],
  <nanobind_std_callable_binding_example>,
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
  ```,
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

What remains however is that the resulting function remains a Python object that doesn't directly expose the compiled code to the #cpp side. It can be passed through nanobind as a callback, but calling it still requires the Python interpreter and the data still must be transformed to Python data types. The JIT compilation therefore only speeds up the actual execution of the callback body. 

#code1(
  [Example of a callback Python function decorated with `@jit` in nopython mode.],
  <numba_jit_example>,
```python
import numpy as np
from numba import njit

FACTOR = 2.0

@jit(nopython=True)
def _nb_jit_double(x: float) -> float:
    return x * FACTOR

vec = bpcode.DoubleVector([1.0, 2.0, 3.0, 4.0, 5.0])
vec.mapAll_stdfunc(_nb_jit_double)
assert vec == [2.0, 4.0, 6.0, 8.0, 10.0]
```,
)

=== Numba `@cfunc`

The `@cfunc` decorator serves a different purpose. Instead of producing a Python-callable function that happens to execute compiled code internally, it generates a native callback with an explicit C-compatible signature. The signature must be specified up front, and the resulting object exposes both a callable wrapper and, more importantly for interoperability, the address of the compiled function. This makes `@cfunc` very interesting as using the pointer directly could completely sidestep Python and offer a path to native callback performance.

From the perspective of PyTNL, yet another binding must be exposed to accommodate the `@cfunc` interface. It could either directly accept the pointer as a raw integer or it can still accept the whole Python object and extract the pointer on the #cpp side. That gives a similar user interface as users can still write a normal Python function, decorate it with `@cfunc`, and pass it to the PyTNL method as if it were just another Python callback.




#code1(
  [Example of a binding accepting a Numba `@cfunc` object. The function pointer is extracted from the `.address` attribute and cast to the matching native signature. The GIL is released for the duration of the loop.],
  <nanobind_cfunc_binding_example>,
  ```cpp
  #include <nanobind/nanobind.h>

  namespace nb = nanobind;

  NB_MODULE(my_module, m) {
      nb::class_<DoubleVector>(m, "DoubleVector")
          ...
          .def("forAll_cfunc",
              [](DoubleVector &self, nb::object cfunc) {
                  auto fp = reinterpret_cast<double(*)(double)>(
                      nb::cast<uintptr_t>(cfunc.attr("address")));
                  {
                      nb::gil_scoped_release release;
                      for (double &x : self.data) {
                          x = fp(x);
                      }
                  }
              }, nb::arg("f"),
              "Call f(x) for every element x via a raw C function pointer "
              "extracted from a Numba @cfunc object.");
  }
  ```,
)

The trade-off is that `@cfunc` is also much more restrictive. The callable must follow an explicitly declared low-level signature, and as the callback is exposed purely as a raw C pointer, it looses lot of the safeties and all the pretty error messages. For example Numba normally catches and handles any exceptions like `ZeroDivisionError`.

=== Numba CUDA <numba_cuda_introduction>

// https://nvidia.github.io/numba-cuda/
For GPU execution, Numba also provides a CUDA backend, commonly referred to as Numba-CUDA. Unlike the CPU-side decorators discussed above, this backend compiles a restricted subset of Python into CUDA kernels and device functions that follow the CUDA execution model. This makes it possible to write GPU kernels in Python syntax, but it also means that the resulting object is fundamentally different from the CPU-side functions discussed above.

// https://nvidia.github.io/numba-cuda/user/kernels.html
With CPU Numba, the `@jit` decorator still produces a Python-callable object, and `@cfunc` can produce a host-side function pointer with a conventional scalar signature. A function decorated with `@cuda.jit` is neither of these. It is a kernel launch object, that is, a GPU function meant to be invoked from host code. This has two immediate consequences relevant to PyTNL:

- Kernels cannot directly return values. All results must be written to one or more arrays in device memory passed as arguments, even when the logical result is just a single scalar.
- Kernels must be launched with an explicit execution configuration, that is, the number of blocks and threads to execute. This configuration is chosen at launch time and different launch sizes do not require recompilation.

The code listing below (@numba_cuda_kernel_launch_example) shows the typical structure of such a launch.

#code1(
  [A minimal Numba-CUDA kernel launched over a CuPy array.],
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
  ```,
)

These properties mean that the callback-based approach described above for CPU execution does not carry over naturally to the GPU case. A CUDA kernel is not something that can be passed through `mapAll` or a similar higher-order binding as if it were just another callable. Even if the launch configuration were threaded through such an interface, the kernel would still not match the scalar callback shape expected by the binding layer, and it would still need direct access to device memory for both inputs and outputs.

If a GPU-backed container is to interoperate with Numba-CUDA realistically, the correct analogue is therefore not passing a kernel through the existing callback interface, but sharing the underlying GPU memory and launching the kernel over that memory from Python. This different execution model is explored in the next chapter and, interestingly, turns out to be quite applicable on the CPU side as well.

== NVRTC <nvrtc_introduction>

// https://docs.nvidia.com/cuda/nvrtc/index.html
NVRTC is NVIDIA's runtime GPU compilation library for CUDA C++. It allows users to compile CUDA code from strings at runtime, producing executable code that can be loaded and invoked from the host.
NVIDIA itself promotes NVRTC as one of the only ways to achieve runtime compilation of CUDA code without the need to spawn a new process executing `nvcc` at runtime, which according to their documentation is an approach with a couple of drawbacks:

- The compilation overhead tends to be higher then necessary.
- End users are required to have `nvcc` and related build tools setup on their system.

NVRTC addresses both of these issues by providing a library interface to the CUDA compilation process. It allows users to compile CUDA code directly from their application, without the need for external tools or processes.

// https://developer.nvidia.com/cuda/python
// https://nvidia.github.io/cuda-python/13.1.1/index.html
// https://nvidia.github.io/cuda-python/cuda-bindings/13.1.1/
The compiler itself is distributed as a #cpp library to be invoked from #cpp code. However, several Python bindings to NVRTC already exist. NVIDIA itself maintains a couple of them under it's CUDA Python libraries. The most direct and low level binding is offered through the `cuda.bindings` module of the `cuda-python` package. It provides almost a one-to-one mapping of the NVRTC API, allowing users to manage the entire compilation and linking process from Python themselves.

As the code snippet below (@nvrtc_cuda_bindings_example) shows, the complete control over the process is a tradeoff that costs a of convenience and requires good understanding the NVRTC API. To launch the CUDA kernel, the user must also manually load the resulting PTX code into a CUDA module, retrieve the kernel function, prepare device memory, copy the data into it and finally launch it with valid configuration.

#code1(
  [Example of using `cuda.bindings` to compile a #cpp string in the `saxpy` variable into a launchable CUDA kernel.],
  <nvrtc_cuda_bindings_example>,
  ```python
  # Initialize CUDA Driver API
  checkCudaErrors(driver.cuInit(0))

  # Retrieve handle for device 0
  cuDevice = checkCudaErrors(driver.cuDeviceGet(0))

  # Derive target architecture for device 0
  major = checkCudaErrors(driver.cuDeviceGetAttribute(driver.CUdevice_attribute.CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MAJOR, cuDevice))
  minor = checkCudaErrors(driver.cuDeviceGetAttribute(driver.CUdevice_attribute.CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MINOR, cuDevice))
  arch_arg = bytes(f'--gpu-architecture=compute_{major}{minor}', 'ascii')

  # Create program
  prog = checkCudaErrors(nvrtc.nvrtcCreateProgram(str.encode(saxpy), b"saxpy.cu", 0, [], []))

  # Compile program
  opts = [b"--fmad=false", arch_arg]
  checkCudaErrors(nvrtc.nvrtcCompileProgram(prog, 2, opts))

  # Get PTX from compilation
  ptxSize = checkCudaErrors(nvrtc.nvrtcGetPTXSize(prog))
  ptx = b" " * ptxSize
  checkCudaErrors(nvrtc.nvrtcGetPTX(prog, ptx))
  ```,
)

To avoid all that, `cuda.core` module from `cuda-core` package aims to provide a more Pythonic interface. It abstract away a lot of the details and shortens the process to what can be seen in the snippet below (@cuda_core_nvrtc_example). Compared to the previous example, this is the complete code. Although it helps that the memory is managed by CuPy.

#code1(
  [Example of `cuda.core` workflow to compile and launch a custom CUDA kernel. `code` variable holds string with #cpp code.],
  <cuda_core_nvrtc_example>,
  ```python
  import cupy as cp
  from cuda.core import Device, LaunchConfig, Program, ProgramOptions, launch

  dev = Device()
  dev.set_current()
  s = dev.create_stream()

  program_options = ProgramOptions(std="c++17", arch=f"sm_{dev.arch}")
  prog = Program(code, code_type="c++", options=program_options)
  mod = prog.compile("cubin", name_expressions=("vector_add<float>",))

  ker = mod.get_kernel("vector_add<float>")

  # Prepare input/output arrays (using CuPy)
  size = 50000
  rng = cp.random.default_rng()
  a = rng.random(size, dtype=cp.float32)
  b = rng.random(size, dtype=cp.float32)
  c = cp.empty_like(a)

  # Configure launch parameters
  block = 256
  grid = (size + block - 1) // block
  config = LaunchConfig(grid=grid, block=block)

  launch(s, config, ker, a.data.ptr, b.data.ptr, c.data.ptr, cp.uint64(size))
  s.sync()
  ```,
)

// https://docs.cupy.dev/en/v14.0.1/user_guide/kernel.html
The interface can be further simplified and almost reach the convenient usage showcased by Numba-CUDA in the @numba_cuda_introduction. For example `CuPy` library itself provides a couple of kernel wrappers essentially only need the #cpp code string and construct a callable kernel object that looks just like a normal Python function. The last example in this section shows its `ElementWiseKernel` which goes yet one step further and wraps the input #cpp function in a way it can be defined as a pure element-wise operation.

#code1(
  [Example of `cupy.ElementWiseKernel` class to launch a kernel compiled at runtime.],
  <cupy_elemwisekernel_example>,
  ```python
  squared_diff = cp.ElementwiseKernel(
     'float32 x, float32 y',
     'float32 z',
     'z = (x - y) * (x - y)',
     'squared_diff')

  x = cp.arange(10, dtype=np.float32).reshape(2, 5)
  y = cp.arange(5, dtype=np.float32)
  squared_diff(x, y)
  array([[ 0.,  0.,  0.,  0.,  0.],
         [25., 25., 25., 25., 25.]], dtype=float32)
  squared_diff(x, 5)
  array([[25., 16.,  9.,  4.,  1.],
         [ 0.,  1.,  4.,  9., 16.]], dtype=float32)

  z = cp.empty((2, 5), dtype=np.float32)
  squared_diff(x, y, z)
  array([[ 0.,  0.,  0.,  0.,  0.],
         [25., 25., 25., 25., 25.]], dtype=float32)
  ```,
)

=== Requirements for the PyTNL containers

Similarly to the Numba-CUDA case, no matter the library or abstraction used, the NVRTC constructs a CUDA kernel that isn't a classic Python callable. All limitations described in @numba_cuda_introduction apply here as well. Passing the kernel through the nanobind callback interface does not circumvent the Python interpreter or the data conversion between Python and #cpp.

=== Runtime compilation of TNL Higher-order functions

Failures to achieve native performance and GPU execution through callbacks led to a more adventurous idea: what if the runtime compiler was used to compile the entire TNL higher-order function itself, with the user definition baked directly into its body before compilation? On the surface, this appeared to offer the full power of TNL higher-order interfaces while preserving native performance. The user would provide custom logic as a #cpp string, select the desired TNL function, and the compiler would generate a callable function at runtime.

In the end, however, this proved to be a rather naive approach. Even if the runtime compiler managed to compile arbitrary user code in this form, the problem of connecting the already compiled PyTNL module to the newly compiled code would remain. Context capture is not available in any practical sense, because the #cpp string cannot refer to existing Python objects. This again reduces the problem to explicit argument passing and to crossing the language boundary without reintroducing interpreter overhead.

Nevertheless, it was first necessary to determine whether NVRTC could compile a TNL higher-order function at all with the user code baked in. The immediate goal was therefore to test whether the generated source could include TNL's `parallelFor` and substitute the user code directly into its body. In the attempt `cuda.core` module was used as it offers still relatively direct interface with plentiful configuration options while retaining the Python-level convenience.

#code1([Kernel template string used to test NVRTC capabilities.], <nvrtc_kernel_string_template_example>, ```python
_KERNEL_SOURCE = """\
#include <TNL/Algorithms/parallelFor.h>
#include <TNL/Devices/Cuda.h>

extern "C" __global__ void tnl_user_kernel(
    double* __restrict__ data,
    int                  size,
    double               param1,
    double               param2
)
{{
    TNL::Algorithms::parallelFor<TNL::Devices::Cuda>(
        0, size,
        [=] __cuda_callable__ (int i) mutable
        {{
            {lambda_body}
        }}
    );
}}
"""
```)

The first encountered problem was simply exposing the TNL headers to the runtime compiler. NVRTC is designed to be a lightweight and drop-in solution and therefore does not inherit the include paths of the host toolchain. This means that not only the TNL headers, but also the standard library headers and the host compiler's built-in include paths, must be supplied explicitly as compilation options.


// https://docs.nvidia.com/cuda/nvrtc/index.html#language
While inconvenient, this part is still merely tooling. The more important issue is structural: NVRTC is a strictly GPU-side compiler. To quote the documentation, "Unlike the offline nvcc compiler, NVRTC is meant for compiling only device CUDA C++ code. It does not accept host code or host compiler extensions in the input code, unless otherwise noted." This is not a minor implementation detail. It means that NVRTC can only consume code that is already cleanly expressible as device code, whereas TNL is written for the ordinary CUDA compilation model in which a source file may freely rely on both host-side and device-side compilation.

// todo: mention where the testing code is? Is it in some kind of appendix?
In principle one may try to push the source toward NVRTC by adding include paths, by treating unannotated functions as device-callable, or by shadowing problematic standard headers with simplified replacements. These measures are useful because they separate accidental incompatibilities from essential ones. They can help with parsing and can postpone failure. They do not, however, change the compilation model expected by the included library.

Including `TNL/Algorithms/parallelFor.h` does not pull in a small self-contained device utility. It pulls in a substantial part of TNL's backend infrastructure together with ordinary C++ library machinery. That infrastructure is designed under the assumption that host-side CUDA runtime services, host-side support code, and normal C++ library facilities are available somewhere in the build. This assumption is valid for offline compilation with `nvcc`, which coordinates separate host and device compilation phases and later links the result into one executable unit. It is not valid for NVRTC, which sees only a device-side fragment being compiled in isolation at runtime.

==== Jitify

// https://github.com/NVIDIA/jitify
NVIDIA is aware that integrating NVRTC into existing CUDA code can be tricky and maintains a single-header library called Jitify that aims to simplify the process. It addresses many of the issues and, most importantly, provides replacements for standard headers that can be adapted into an NVRTC-safe form. The library is #cpp only, but for demonstration purposes these headers can at least be imported manually and used instead of the standard ones.

With such Jitify-style stubbing, the compilation does indeed progress further, but the compilation still does not reach successful end. The stubs are likely still insufficient which is something that could be improved with more work, but the compilation starts to show errors that can not be easily circumvented. The `parallelFor` implementation includes setting up and launching the compiled Kernel. That however uses CUDA-API functions explicitly declared as `__host__` as the kernels are at the end meant to be launched from host code. And NVRTC just cannot compile and cannot output host code.

==== NVCC

The full `nvcc` compilation seems to remain the only option to compile #cpp including TNL. While the mentioned issues prevail, the compilation time could be mitigated by caching the already used sources and requiring users to have `nvcc` setup is not a problem for current TNL and PyTNL users as it is needed to compile the libraries in the first place.

Using `nvcc` to dynamically compile code at runtime is further explored in @sph_code_generation. Although there it focuses on tackling a different problem, the approach shows some promise for the user defined function and kernels as well. For all the examples mentioned so far however, it would likely be an overkill. If the PyTNL containers could be designed to share the underlying memory, then NVRTC could be used much more in line with what was intended and compile user defined kernels with no TNL dependency that simply operate on memory handled by the PyTNL. This is what next chapter explores.

== Benchmark <function_calling_from_cpp_benchmark>

#todo[Maybe the section could be moved before NVRTC as it doesn't reference it. Yet it does reference the Numba. Numba-cuda however should be close by to the NVRTC... So the numba-cuda and the nvrtc could be moved below together as some kind of GPU section?]

Taking a step back from the kernels and runtime compilation, this section describes a benchmark designed to measure the performance of different approaches of passing user callbacks from Python to #cpp as originally described in @pytnl_nanobind_callbacks. The goal is to determine if the approach could eventually be close enough to desired native performance of standalone TNL code and if not, where the main bottlenecks are. 

Note that as was explored, GPU execution is not really feasibly with this callback model, the benchmark shows only CPU and purely sequential execution. 

The scenarios also do not run on actual PyTNL containers, but on a custom `DoubleVector` class, simple wrapper of `std::vector<double>`. It exposes different methods that apply a user defined operation to each element of the vector. In the first scenario, the operation is a simple multiplication by 2.0. Benchmark compares all the approaches described in @pytnl_nanobind_callbacks and expand them with JIT-compiled Numba variants of the operation. All the JIT variants are warmed up before the benchmark so the timings do not include the compilation time.

For completeness, it also shows a couple of baseline cases. Python list which is chosen as a timing baseline is a pure Python list and for loop multiplying each element by two. The `Python DoubleVector` uses `__get_item__` and `__setitem__` to allow the same Python code to run on the custom class. The `NumPy *= 2.0` case uses NumPy arrays and vectorized multiplication. The `C++ multiplyAll` case is a native #cpp method that multiplies each element by two without any callback.

Results of the first scenario are shown in the @benchmark_scenario_a_table below.

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

Right away, it is clear the the callbacks, with the exception of Numba's `@cfunc`s, are not competitive with the native approaches. They are in fact even slower then the pure Python list iteration, which is the first strong indication the binding overhead and language boundary crossings cause a significant slowdown and the issue is not necessarily the execution speed (i.e., the Python interpreting speed) of the callback body. 

The cases using Numba JIT-compiled functions through `mapAll` methods further confirm this as, surprisingly, they are even slower than the pure Python callbacks. The execution time of the JIT-compiled function itself should very much compete with the native `multiplyAll` method and the fact that the `@cfunc` variants do indeed reach same order of magnitude confirms that. If the bottleneck isn't the callback execution itself, it leaves just the overhead of crossing the data across the language boundary each time the function is called.

It would even explain why the JIT compiled variants are slower then the pure Python callbacks as in them the boundary is in fact crossed twice. The data first cross into Python only to be converted once again into #cpp types for the Numba function. Same thing happens to the return value on the way back.

As last confirmation, the benchmark implements a second scenario with a heavier element-wise compute, namely `sin(x) + cos(x) dot sqrt(|x|+1)`. This should shift the bottleneck more toward the execution of the callback body and away from the language boundary crossing. If that is the case, then the JIT-compiled variants could finally show their advantage and show better relative performance compared to the pure Python callbacks. Results below in the @benchmark_scenario_b_table confirm this. 

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

To end the on a good note, the benchmark also brings a couple of good news. The difference between different binding methods is negligible, which means that the choice between `nb::object`, `nb::callable` and `std::function` can be made based on convenience and flexibility rather than performance. 

And most importantly, the `@cfunc` variants confirm that JIT compilation can indeed bring the performance of Python callbacks much closer to native code and as such is definitely a step in the right direction. In the second scenarios, they are actually on par with the native `heavyComputeAll` method and clearly outperform even the Numpy ufuncs.

Of course, `@cfunc` itself comes with its own limitations and maybe more importantly, doesn't have a natural counterpart in Numba for GPU execution. The next chapter therefore explores an alternative approach that would avoid the repeated language crossings that looks to be the primary bottleneck.  

== Other Python libraries

=== CuPy

=== Polars

// https://docs.pola.rs/user-guide/expressions/user-defined-python-functions/#processing-a-whole-series-with-map_batches

=== NumPy

// TODO: mention inspiration from some libraries described above?
=== JAX
