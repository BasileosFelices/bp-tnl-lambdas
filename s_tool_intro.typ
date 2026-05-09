#import "ctufit-thesis.typ": *
#import "@preview/dashy-todo:0.1.3": todo

= Background and \ related technologies <tool-intro-chapter>

== Template Numerical Library

// https://doi.org/10.14311/AP.2021.61.0122
The Template Numerical Library (TNL) is a #cpp library for numerical simulations that aims to combine high computational efficiency with a user-friendly and consistent programming interface. Its design targets modern parallel hardware, including multi-core CPUs, GPUs, and distributed-memory systems, while avoiding the overheads that often follow from traditional object-oriented abstractions. Instead, TNL relies on #cpp templates and their specialization mechanisms to generate architecture-specific code at compile time, making it possible to keep a unified interface without sacrificing performance. #cite(<c_Oberhuber_Klinkovský_Fučík_2021>)

// This design is particularly important for GPU computing, where efficient implementations require careful control over memory layout, data transfer, and parallel execution patterns. In many numerical applications, especially those involving sparse matrices, iterative solvers, or mesh-based discretizations, adapting algorithms to accelerators is not a minor extension but a substantial redesign. TNL addresses this difficulty by providing data structures and algorithms that are implemented with these architectural differences already in mind.

=== Arrays and NDArrays

Arrays are basic data structures for memory management in TNL and they are the main focus of this thesis. They rely on template parameters not just for the data type but also for the Device on which the data is stored. This design provides consistent interface although the underlying memory management differs significantly between CPU and GPU. The differences however still surface from time to time, not all methods are available for all devices and as will be explored in later chapters, different approaches may be required to support the same features on different devices.

NDArrays are a higher-level abstraction built on top of classic arrays that provide more convenient interface for multi-dimensional data. While the examples in this work often show just one-dimensional arrays for simplicity, the goal in all cases is full support for these multi-dimensional structures. Multi-dimensional arrays are the primary data structures in most Python numerical libraries, and supporting them is a key requirement if PyTNL is to be a useful tool for Python users.   

== PyTNL

PyTNL is a Python binding layer for selected TNL components. PyTNL aims to use TNL's effective backend and following the original focus on user experience, provide even more accessible interface that uses Python's expressiveness and convenience. As of beginning of 2026, PyTNL is still under active development and the set of exported features is still evolving. The focused Arrays and NDArrays are already available. 

=== nanobind

For the bindings, PyTNL relies on nanobind, small binding library for exposing #cpp types in Python and vice versa. Its goal is to be a modern and efficient, maybe bit opinionated, alternative to more established pybind11 or Boost.Python. According to benchmarks, nanobind compiles in a shorter amount of time, produces smaller libraries and has better runtime performance. #cite(<c_nanobind>)

What may prove challenging is that as part of its philosophy, nanobind does not intend to be be usable for #cpp codebases and instead focuses on providing clean and efficient bindings just for a smaller #cpp subset. The philosophy explicitly states: The codebase has to adapt to the binding tool and not the other way around. Next chapter will explore how fitting match TNL is and if nanobind's design may impose some limitations on the features current TNL can expose to Python.

== Compute Unified Device Architecture

// https://developer.nvidia.com/cuda
// source for "proprietary" https://www.theregister.com/2021/11/10/nvidia_cuda_silicon/
// https://docs.nvidia.com/cuda/cuda-programming-guide/01-introduction/introduction.html
The Compute Unified Device Architecture (CUDA) is a proprietary and closed-source parallel computing platform introduced in 2006 developed by the NVIDIA Corporation that allows using GPUs for accelerated computing. The toolkit allows developers to write GPU accelerated applications in numerous languages including C, #cpp or Python and is adopted by many existing libraries and frameworks. #mcite(<c_cuda-programming-guide>, <c_cuda-platform>, <c_theregister-cuda-silicon>)

=== Expected heterogeneous system

// https://docs.nvidia.com/cuda/cuda-programming-guide/01-introduction/programming-model.html
The CUDA programming model is not strictly about GPU execution, in fact it assumes a heterogeneous system where the CPU (host) and GPU (device) work together. Both CPU and GPU have their own memory spaces called _host memory_ and _device memory_, respectively. In some systems, the memory may be unified and conversely some systems may have multiple GPUs or even CPUs, each with their own memory space, but for simplicity, the works only considers the most common case of a single CPU and a single GPU with separate memory spaces. #cite(<c_cuda-programming-guide>)

CUDA applications execute code on the GPU but they always start on the CPU. Code running on the CPU is called host code and typically handles the orchestration of the application, memory transfers, starting GPU execution and processing the results of it. 

On the other hand, code running on the GPU is called device code. For historical reasons, functions executed on the GPU are called kernels and starting them is often referred to as launching a kernel. The distinction is important because the kernels are quite different from regular CPU functions. Instead of being a set of instructions executed sequentially, kernel is executed by many threads in parallel that must carefully coordinate themselves through shared memory.

=== GPU hardware model

Like any programming model, CUDA relies on a simplified view of the underlying hardware. For programming purposes, the GPU can be seen as a collection of Streaming Multiprocessors (SMs), which may be further organized into Graphics Processing Clusters (GPCs). 

The exact number of functional units and the sizes of these memory resources differ across GPU architectures, but the same general model remains useful for understanding how CUDA programs execute. #cite(<c_cuda-programming-guide>)

#figure(
    caption: [Diagram of single CPU and GPU system model. #cite(<c_cuda-programming-guide>)],
    // placement: bottom,
    image("assets/gpu-cpu-system-diagram.png", width: 90%),
) <cuda_thread_grid_diagram>

=== CUDA threads and blocks

// https://docs.nvidia.com/cuda/cuda-programming-guide/01-introduction/programming-model.html#thread-blocks-and-grids
As mentioned, kernels are executed by many threads in parallel. These threads are organized into blocks and blocks are organized into grids. Both blocks and grids can have one, two, or three dimensions which can simplify mapping of the threads to data structures. But in a grid, all thread blocks need to have the same number of threads and dimensions. #cite(<c_cuda-programming-guide>)

#figure(
    caption: [Grid of Thread Blocks. Each arrow represents a thread. #cite(<c_cuda-programming-guide>)],
    image("assets/cuda_grid_threads.png"),
) <cuda_thread_grid_diagram>

To launch a kernel, the programmer must specify the number of requested thread blocks and number of threads per block as part of the so called execution configuration. Each thread can later determine its location within the block as well as in the whole grid through built-in variables `threadIdx`, `blockIdx`, and `blockDim`. This allows threads to compute their global thread ID, which is often used to determine which part of the work the thread is responsible for.

$ "globalId" = "blockIdx" times "blockDim" + "threadIdx" $

During execution, CUDA assigns the blocks to available streaming multiprocessors (SMs) on the GPU in no guaranteed order. The threads within the block then execute concurrently on the same SM. This architecture allows arbitrarily large grids to be launched, as even smaller GPUs with fewer SMs can execute the blocks in batches. However, it also means there can be no dependencies between different thread blocks. 

=== Compiler infrastructure

// https://docs.nvidia.com/cuda/cuda-programming-guide/01-introduction/cuda-platform.html
// https://docs.nvidia.com/cuda/cuda-programming-guide/02-basics/nvcc.html
// https://docs.nvidia.com/cuda/cuda-compiler-driver-nvcc/index.html
To utilize GPU with a library like TNL, the code has to be compiled with a compatible compiler that can generate the device code. The NVIDIA CUDA Compiler (`nvcc`) is a typical entry point for compilation of CUDA C/#cpp code. Compared to traditional compilers, `nvcc` itself is more of a driver that orchestrates the whole compilation process. 
#mcite(<c_cuda-programming-guide>, <c_cuda-nvcc>)

Source files compiled with `nvcc` can contain both host code and device code. In the initial phase, `nvcc` separates the targets and dispatches their compilation  to the device and the host compilers, respectively. For host code, `nvcc` invokes a standard C/#cpp compiler (like `g++`), which needs to be present and accessible on the system. Pure host code is compiled directly, and the calls to GPU code are linked at link-time. 

The GPU compilation process first compiles #cpp device code into _Parallel Thread Execution_ (PTX) assembly. A high-level assembly language for NVIDIA GPUs. This happens in two steps. First, the code is compiled by the compiler front-end into NVVM IR, an intermediate representation that abstracts away the original source language. Then NVVM, LLVM based compiler, generates the PTX. This can be done multiple times for each desired virtual instruction set architecture (ISA), possibly resulting in multiple PTX files. 

The PTX files are then passed to `ptxas` tool, which generates the final GPU binary code (`cubin`) for specific hardware. This can once again be done multiple times for different targets. Finally, all these targets can be embedded into a single fat binary to support a range of GPU architectures. One of the strengths of the additional PTX layer is that if compatible PTX is present, the GPU driver can JIT compile additional `cubin`s for newer architectures without needing to recompile the original source.

#figure(
    caption: [`nvcc` compilation workflow with multiple PTX and Cubin architectures. #cite(<c_cuda-programming-guide>)],
    image("assets/nvcc_execution.png")
) <nvcc_compilation_diagram>

`nvcc` coordinates this entire process, usually hiding the complexity from its user. However, when it comes to just-in-time compilation in later chapters, it may be useful to understand the underlying phases as it is not strictly required to always go through all of them. 

// todo: keep this??
== Similar libraries

PyTNL is not the first library to attempt to provide a Python interface for a #cpp library. And pretty much all of the existing numerical libraries in Python are in fact bindings to some underlying C or #cpp codebase.

Many of these libraries are battle tested and may provide useful inspiration for PyTNL. Here is a brief overview of some of the most popular ones that this work takes inspiration and even directly uses in some of the examples.

=== NumPy

NumPy is the foundational array library of the Python scientific-computing ecosystem. It provides a compact and efficient representation of homogeneous $n$-dimensional arrays together with vectorized operations, broadcasting, and a large collection of numerical routines. In practice, many higher-level Python libraries build on top of NumPy arrays or adopt its API conventions, which makes it a natural baseline for any Python interface targeting numerical work.

=== CuPy

CuPy can be understood as a GPU-oriented counterpart to NumPy. It offers an array API intentionally close to NumPy's, but stores data on CUDA devices and dispatches operations to GPU kernels and CUDA libraries such as cuBLAS or cuFFT. This close compatibility is particularly relevant here because it shows how a Python library can expose high-performance CUDA functionality while still feeling familiar to users accustomed to NumPy-style programming.

=== JAX

JAX combines a NumPy-like programming model with automatic differentiation and just-in-time compilation. Rather than focusing only on array storage and eager execution, it emphasizes whole-program transformations, which makes it especially useful in machine learning and differentiable scientific computing. For this thesis, it is interesting mainly as an example of how a high-level Python interface can drive aggressive compilation and optimization in the backend.

=== Polars

Polars is a DataFrame library implemented primarily in Rust and designed around a columnar execution model. Although it targets tabular data processing rather than numerical kernels in the same sense as NumPy or CuPy, it is still a useful comparison point because it demonstrates how a high-performance native backend can be wrapped in a Python API without exposing the underlying implementation complexity to the user.