#import "ctufit-thesis.typ": *
#import "@preview/dashy-todo:0.1.3": todo

= Introduction

== Template Numerical Library

// https://doi.org/10.14311/AP.2021.61.0122
The Template Numerical Library (TNL) is a #cpp library for numerical simulations that aims to combine high computational efficiency with a user-friendly and consistent programming interface. Its design targets modern parallel hardware, including multi-core CPUs, GPUs, and distributed-memory systems, while avoiding the overheads that often follow from traditional object-oriented abstractions. Instead, TNL relies on #cpp templates and their specialization mechanisms to generate architecture-specific code at compile time, making it possible to keep a unified interface without sacrificing performance.

This design is particularly important for GPU computing, where efficient implementations require careful control over memory layout, data transfer, and parallel execution patterns. In many numerical applications, especially those involving sparse matrices, iterative solvers, or mesh-based discretizations, adapting algorithms to accelerators is not a minor extension but a substantial redesign. TNL addresses this difficulty by providing data structures and algorithms that are implemented with these architectural differences already in mind.

=== Arrays and NDArrays

Arrays are basic data structures for memory management in TNL and they are the main focus of this thesis. They rely on template parameters not just for the data type but also for the Device on which the data is stored. This design provides consistent interface although the underlying memory management differs significantly between CPU and GPU. The differences however still surface from time to time, not all methods are available for all devices and as will be explored in later chapters, different approaches may be required to support the same feature on different device.

NDArrays are a higher-level abstraction built on top of classic arrays that provide nicer interface for multi-dimensional data. While the examples in this work often show just one-dimensional arrays for simplicity, the goal in all cases is full support for these multi-dimensional structures. As multi-dimensional arrays are the primary data structures in most Python numerical libraries, and supporting them is a key requirement if PyTNL is to be a useful tool for Python users.   

== PyTNL

Speaking of it, PyTNL is a Python binding layer for selected TNL components. PyTNL aims to use TNL's effective backend and following the original focus on user experience, provide even more accessible interface that uses Python's expressiveness and convenience. As of beginning of 2026, PyTNL is still under active development and the set of exported features is still evolving. The focused arrays and NDArrays are already available. 

=== Nanobind

For the bindings, PyTNL relies on nanobind, small binding library for exposing #cpp types in Python and vice versa. It's goal is to be a modern and efficient, maybe bit opinionated, alternative to more established pybind11 or Boost.Python. According to authors, nanobind compiles in a shorter amount of time, produces smaller libraries and has better runtime performance.

What may prove challenging is that as part of it's philosophy, nanobind does not intend to be be usable for #cpp codebases and instead focuses on providing clean and efficient bindings just for a smaller #cpp subset. The philosophy explicitly states: The codebase has to adapt to the binding tool and not the other way around. Next chapter will explore how fitting match TNL is and if nanobind's design may impose some limitations on the features current TNL can expose to Python.

// http://hdl.handle.net/10467/116916
== Compute Unified Device Architecture

#todo[Heavily derived or directly copied from http://hdl.handle.net/10467/116916. Is that ok if cited?]

The Compute Unified Device Architecture (CUDA) is a proprietary and closed-source parallel computing platform and an application programming interface (API) developed by the NVIDIA Corporation that allows software to use GPUs for general-purpose programming (GPGPU). C, C++, Python, and Fortran programming languages are compatible with the CUDA, making it easy to access parallel architecture resources.

==== Thread hierarchy

// http://hdl.handle.net/10467/116916
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
// https://docs.nvidia.com/cuda/cuda-programming-guide/02-basics/nvcc.html
=== Compiler infrastructure

To utilize GPU with a library like TNL, the code has to be compiled with a compatible compiler that can generate GPU code. The NVIDIA CUDA Compiler (`nvcc`) is a typical entry point for compilation of CUDA C/#cpp code as well as parallel thread execution (PTX) assembly code. Compared to traditional compilers, `nvcc` itself is more of a driver that orchestrates the whole compilation process. 

Source files compiled with `nvcc` can contain both host code, executed on the CPU, and device code, executed on the GPU. In the initial phase, `nvcc` separates the targets and dispatches their compilation  to the GPU and the host compilers, respectively. For host code, `nvcc` invokes a standard C/#cpp compiler (like `g++`), which needs to be present and accessible on the system. Pure host code is compiled directly, and the calls to GPU code are linked at link-time. 

The GPU compilation process compiles #cpp device code into PTX assembly in two steps. First, the code is compiled by the compiler front-end into NVVM IR, an intermediate representation that abstracts away the original source language. Then, it the NVVM, LLVM based, compiler generates the PTX, low-level assembly language containing GPU instructions. This can be done multiple times for each desired virtual instruction set architecture, possibly resulting in multiple PTX files. 

The PTX files are then passed to `ptxas` tool, which generates the final GPU binary code (`cubin`) for specific hardware. This can once again be done multiple times for different targets. Finally, all these targets can be embedded into a single fat binary to support a range of GPU architectures. 

#figure(
    caption: [`nvcc` compilation workflow with multiple PTX and Cubin architectures.],
    image("assets/nvcc_execution.png")
) <nvcc_compilation_diagram>

`nvcc` coordinates this entire process, usually hiding the complexity from it's user. However, when it comes to Just-in-time compilation in later chapters, it may be useful to understand the underlying phases as it's not strictly required to always go through all of them. 

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

