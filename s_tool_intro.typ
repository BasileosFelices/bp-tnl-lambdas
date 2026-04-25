#import "ctufit-thesis.typ": *
#import "@preview/dashy-todo:0.1.3": todo

= Introduction

== CUDA, GPU computations

// http://hdl.handle.net/10467/116916
=== Compute Unified Device Architecture

The Compute Unified Device Architecture (CUDA) is a proprietary and closed-source parallel computing platform and an application programming interface (API) developed by the NVIDIA Corporation that allows software to use GPUs for general-purpose programming (GPGPU). C, C++, Python, and Fortran programming languages are compatible with the CUDA, making it easy to access parallel architecture resources.

==== Thread hierarchy

The CUDA architecture comprises a hierarchical structure that includes threads, blocks, and grids, which facilitates parallel computation:

- *Threads* in CUDA are the smallest units of execution. Each thread executes an instance of a kernel function, which is a function written to run on the GPU. Threads operate concurrently, performing computations on different pieces of data. Key characteristics of CUDA threads include:
    - *Identification:* Each thread has a unique thread ID, which is accessible within the kernel through the built-in variable `threadIdx`. This ID helps in indexing and accessing specific data elements in parallel.
    - *Scope:* Threads have access to different types of memory, including local memory (private to each thread) and shared memory (shared among threads within a block, denoted in the C++ programming language by the keyword `__shared__`).
    - *Synchronization:* Threads within the same block can synchronize their execution using synchronization functions like `__syncthreads()`. This ensures that all threads in the block reach a certain point before any thread proceeds, facilitating coordinated data sharing and avoiding race conditions.

- *Blocks* are groups of threads that can operate by sharing data through shared memory and synchronizing their execution. Each block has a unique block ID, accessible via the `blockIdx` variable. Key characteristics of CUDA blocks include:
    - *Dimension:* Blocks can be one-dimensional, two-dimensional, or three-dimensional. This flexibility allows for efficient mapping of threads to multi-dimensional data structures.
    - *Size:* The maximum number of threads per block is limited by the GPU architecture, typically 1024 threads per block on modern GPUs. This limit necessitates careful design to balance parallelism and resource usage.
    - *Shared memory:* Threads within a block can communicate and share data via shared memory. Compared to global memory, shared memory is particularly useful for algorithms that require frequent data exchange among threads.

- *Grids* are collections of blocks that execute the same kernel function. The grid structure allows for the parallel execution of a large number of blocks, scaling up the parallelism to handle extensive computational tasks. Key characteristics of CUDA grids include:
    - *Dimension:* Similar to blocks, grids can be one-dimensional, two-dimensional, or three-dimensional. This allows for efficient organization and indexing of large datasets.
    - *Global scope:* Each block within a grid has a unique ID, accessible via the `blockIdx` variable. Combined with the thread ID, accessible via the `threadIdx` variable, this allows for global indexing of threads across the entire grid.
    - *Scalability:* The grid structure provides a scalable framework for parallel computation. By adjusting the number of blocks and threads, developers can optimize the execution to match the capabilities of the GPU and the requirements of the problem being solved.

==== CUDA Kernel

A CUDA kernel is a function that runs on a GPU. Unlike regular functions that execute on the CPU, a CUDA kernel is designed to be executed by many threads in parallel on a GPU. Consider the following example of a kernel declaration below:

```cpp
__global__ void kernelFunction( parameters ) {
    int gtidx = blockIdx.x * blockDim.x + threadIdx.x; // Calculate the global thread ID

    // Perform computation
}
```

As can be seen in the example code block above, the CUDA kernel kernelFunction is initialized with the `__global__` keyword, indicating that kernelFunction is a kernel function that runs on the device (GPU) and is called from the host (CPU).

Launching a CUDA kernel requires specifying the execution configuration, including the number of blocks in a grid and the number of threads per block. For example:

```cpp
int numBlocks = 16;
int numThreadsPerBlock = 256;

kernelFunction<<< numBlocks, numThreadsPerBlock >>>( parameters );
```

Here in the example code block, the name of the CUDA kernel kernelFunction is specified, followed by the <<< ... >>> execution syntax, where the number of available thread blocks and threads per block are specified.

// TODO: fact check and maybe rewrite the ending 
=== Compiler infrastructure

// Sources:
// https://docs.nvidia.com/cuda/cuda-compiler-driver-nvcc/index.html#purpose-of-nvcc
The NVIDIA CUDA compiler stack is best understood as a layered infrastructure rather than as a single compiler. At the top stands `nvcc`, which is primarily a compiler driver. Its task is to orchestrate preprocessing, invoke the host compiler for ordinary C++ code, invoke NVIDIA's device-side compilation stages for CUDA kernels, and package the resulting device images together with the host object code. For offline builds, `nvcc` is therefore the main entry point, but much of the actual translation work is delegated to lower-level components.

// Sources:
// https://docs.nvidia.com/cuda/cuda-compiler-driver-nvcc/index.html#cuda-sources
// https://docs.nvidia.com/cuda/cuda-compiler-driver-nvcc/index.html#the-cuda-compilation-trajectory
A CUDA source file typically contains both host code and device code. During compilation, `nvcc` preprocesses the translation unit for device compilation, extracts the device-relevant parts, and compiles them into PTX and/or a device binary (`cubin`). It then preprocesses the source again for host compilation, rewrites CUDA-specific constructs such as kernel launch syntax into ordinary host-side runtime calls, embeds the produced device images into a fatbinary, and forwards the generated host-side source to a conventional C++ compiler such as `g++` or `clang++`. In this sense, `nvcc` does not replace the host compiler; it coordinates the host toolchain with NVIDIA's device compiler.

// Sources:
// https://docs.nvidia.com/cuda/nvvm-ir-spec/index.html#introduction
// https://docs.nvidia.com/cuda/libnvvm-api/index.html#introduction
// https://docs.nvidia.com/cuda/libnvvm-api/index.html#compilation
Between the CUDA front end and the PTX stage lies NVVM. `NVVM IR` is NVIDIA's LLVM-based intermediate representation for GPU programs. This layer is important because it decouples the high-level CUDA language front end from the PTX back end and enables analysis, verification, optimization, and link-time transformations on a machine-independent representation. The `libNVVM` interface accepts NVVM IR modules, links them at the IR level, and compiles the resulting program to PTX. Device code can also be matched with auxiliary device libraries at this stage, such as the `libdevice` implementations of mathematical routines. One can therefore say that the CUDA front end is responsible for understanding CUDA C++ syntax and semantics, while NVVM takes over once the program has been lowered to NVVM IR and performs the main middle-end and PTX code-generation work.

// Sources:
// https://docs.nvidia.com/cuda/cuda-compiler-driver-nvcc/index.html#gpu-compilation
// https://docs.nvidia.com/cuda/cuda-compiler-driver-nvcc/index.html#just-in-time-compilation
// https://docs.nvidia.com/cuda/cuda-compiler-driver-nvcc/index.html#fatbinaries
// https://docs.nvidia.com/cuda/cuda-compiler-driver-nvcc/index.html#ptxas-options
PTX itself is still not final machine code; it is a virtual instruction set architecture that describes code for a virtual GPU architecture such as `compute_80`. From PTX, the `ptxas` assembler produces architecture-specific machine code for a concrete target such as `sm_80`, stored in a `cubin`. This two-stage model is central to CUDA compatibility: a fatbinary may contain several precompiled cubins for known architectures together with PTX for forward compatibility. At program startup or kernel launch, the CUDA runtime or driver selects the most suitable embedded image; if no matching cubin is available, it can just-in-time compile the PTX for the actual GPU.

// Sources:
// https://docs.nvidia.com/cuda/cuda-compiler-driver-nvcc/index.html#using-separate-compilation-in-cuda
// https://docs.nvidia.com/cuda/cuda-compiler-driver-nvcc/index.html#nvcc-options-for-separate-compilation
// https://docs.nvidia.com/cuda/cuda-compiler-driver-nvcc/index.html#dlink-time-opt
For multi-file programs, the device path can include one more stage, namely `nvlink`, the device linker. In whole-program mode, executable device code is embedded directly into host objects. In separate-compilation mode (`-rdc=true`), host objects instead carry relocatable device code, and `nvlink` resolves device-side references across translation units before the final host link step. A related optimization mode is device link-time optimization (`-dlto`), where higher-level intermediate code is preserved until link time so that cross-file optimization can still be performed before final code generation.

// Sources:
// https://docs.nvidia.com/cuda/nvrtc/index.html#introduction
// https://docs.nvidia.com/cuda/nvrtc/index.html#language
// https://docs.nvidia.com/cuda/nvrtc/index.html#compilation
// https://docs.nvidia.com/cuda/nvrtc/index.html#example-device-lto-link-time-optimization
Besides `nvcc`, NVIDIA also provides `NVRTC`, a runtime compilation library. Unlike `nvcc`, `NVRTC` is intended for just-in-time compilation inside an application and compiles only device CUDA C++ code provided as source strings; it does not compile host code. Its outputs are typically PTX, cubin, or LTO IR, which can then be loaded by the CUDA driver or linked further with tools such as `nvJitLink`. Consequently, `nvcc`, `NVRTC`, `NVVM`, `ptxas`, and `nvlink` should be viewed as cooperating layers of one compiler infrastructure rather than as interchangeable tools.

== Introduction to TNL

The Template Numerical Library (TNL) is a #cpp library for numerical simulations that aims to combine high computational efficiency with a user-friendly and consistent programming interface. Its design targets modern parallel hardware, including multi-core CPUs, GPUs, and distributed-memory systems, while avoiding the overheads that often follow from traditional object-oriented abstractions. Instead, TNL relies on #cpp templates and their specialization mechanisms to generate architecture-specific code at compile time, making it possible to keep a unified interface without sacrificing performance.

This design is particularly important for GPU computing, where efficient implementations require careful control over memory layout, data transfer, and parallel execution patterns. In many numerical applications, especially those involving sparse matrices, iterative solvers, or mesh-based discretizations, adapting algorithms to accelerators is not a minor extension but a substantial redesign. TNL addresses this difficulty by providing data structures and algorithms that are implemented with these architectural differences in mind, while still presenting a coherent programming model to the user.

More broadly, TNL aims to offer a wider and more coherent environment for #cpp high-performance computing than narrowly specialized libraries. It combines support for common parallel patterns, linear algebra operations, sparse matrices, and numerical solvers under a unified templated interface inspired by the #cpp standard library. This emphasis on consistency and abstraction naturally opens the way to higher-level interfaces that improve usability without giving up the performance advantages of the original library.

== PyTNL

One such interface is PyTNL, a Python binding layer for selected TNL components. PyTNL brings TNL into Python-driven workflows, where the convenience and expressiveness of Python can be combined with performance-critical kernels implemented in compiled backends. In this sense, PyTNL can be seen as a further extension of TNL's original focus on user experience: it does not replace the underlying high-performance #cpp library, but makes its selected building blocks more accessible for prototyping, orchestration of numerical workflows, and interoperability with other tools in the Python scientific ecosystem.

At the same time, PyTNL is still under active development and its interface is not yet final. The currently available bindings expose only selected parts of TNL, and the exact set of supported classes and functions may evolve over time. This makes PyTNL both a practical tool and a research opportunity: it already enables useful Python-facing workflows, but it also raises open questions about how far a performance-oriented templated #cpp library can be exposed in a way that remains both efficient and convenient to use.

This thesis focuses on that problem. Its goal is not only to extend PyTNL with additional bindings, but mainly to explore how more advanced TNL abstractions can be made available from Python, especially higher-order operations that in native TNL rely on #cpp lambda functions. A particularly attractive objective is to allow users to express custom computation in Python while still executing performance-critical parts through efficient compiled mechanisms. The central challenge is therefore to improve the user experience of TNL-based workflows without turning the Python interface into a thin but slow wrapper over the original library.

To address this challenge, the thesis examines multiple approaches to crossing the language boundary between Python and #cpp. It first considers direct invocation of Python callables from the native side, then evaluates just-in-time compilation techniques and data interchange protocols that make it possible to operate on TNL-managed memory more directly from Python. These ideas are finally discussed in the context of practical workflows, including the TNL-SPH solver, where improving accessibility and reducing the amount of required boilerplate can significantly enhance the overall usability of the library.

== Similar libraries

#todo[The others should be expanded or scrapped all together I'd say.]

PyTNL is not the first library to attempt to provide a Python interface for a #cpp library. And pretty much all of the existing numerical libraries in Python are in fact bindings to some underlying C or #cpp codebase.

Many of these libraries are battle tested and may provide useful inspiration for PyTNL. Here is a brief overview of some of the most popular ones that this work takes inspiration and even directly uses in some of the examples.

=== NumPy

NumPy is the foundational array library of the Python scientific-computing ecosystem. It provides a compact and efficient representation of homogeneous $n$-dimensional arrays together with vectorized operations, broadcasting, and a large collection of numerical routines. In practice, many higher-level Python libraries build on top of NumPy arrays or adopt its API conventions, which makes it a natural baseline for any Python interface targeting numerical work.

=== CuPy

CuPy can be understood as a GPU-oriented counterpart to NumPy. It offers an array API intentionally close to NumPy's, but stores data on CUDA devices and dispatches operations to GPU kernels and CUDA libraries such as cuBLAS or cuFFT. This close compatibility is particularly relevant here because it shows how a Python library can expose high-performance CUDA functionality while still feeling familiar to users accustomed to NumPy-style programming.

=== Others

==== JAX

JAX combines a NumPy-like programming model with automatic differentiation and just-in-time compilation. Rather than focusing only on array storage and eager execution, it emphasizes whole-program transformations, which makes it especially useful in machine learning and differentiable scientific computing. For this thesis, it is interesting mainly as an example of how a high-level Python interface can drive aggressive compilation and optimization in the backend.

==== Polars

Polars is a DataFrame library implemented primarily in Rust and designed around a columnar execution model. Although it targets tabular data processing rather than numerical kernels in the same sense as NumPy or CuPy, it is still a useful comparison point because it demonstrates how a high-performance native backend can be wrapped in a Python API without exposing the underlying implementation complexity to the user.

