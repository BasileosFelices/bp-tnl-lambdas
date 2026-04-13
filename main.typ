#import "ctufit-thesis.typ": *
#import "@preview/fletcher:0.5.7" as fletcher: diagram, node, edge

#let cpp = [C++]

// TODO
#let acknowledgment = [
  TODO: Poděkování
]

#let declaration = [
  TODO
  // I hereby declare that the presented thesis is my own work and that I have cited all sources of information in accordance with the Guideline for adhering to ethical principles when elaborating an academic final thesis. I declare that I have used AI tools during the preparation and writing of my thesis. I have verified the generated content. I confirm that I am aware that I am fully responsible for the content of the thesis.
  // \
  // \
  // I acknowledge that my thesis is subject to the rights and obligations stipulated by the Act No. 121/2000 Coll., the Copyright Act, as amended. In accordance with Section 2373(2) of Act No. 89/2012 Coll., the Civil Code, as amended, I hereby grant a non-exclusive authorization (licence) to utilize this thesis, including all computer programs that are part of it or attached to it and all documentation thereof (hereinafter collectively referred to as the "Work"), to any and all persons who wish to use the Work. Such persons are entitled to use the Work in any manner that does not diminish the value of the Work and for any purpose (including use for profit). This authorisation is unlimited in time, territory and quantity.
]

#let abstract-ENG = [
  TODO
]

#let abstract-CZE = [
  TODO
]

#show: ctufit-thesis.with(
  title: "Interfaces for TNL library data structures and algorithms in Python and Julia",
  author-full: "Filip Špelina",
  author-surnames: "Špelina",
  author-given-names: "Filip",
  department: "Department of Software Engineering",
  study-program: "Informatics",
  specialization: "Software Engineering",
  supervisor: "doc. Ing. Tomáš Oberhuber Ph.D.",
  year: "2026",
  declaration: declaration,
  declaration-place: "Prague",
  // TODO: CHECK DATE
  declaration-date: datetime.today(),
  acknowledgment: acknowledgment,
  abstract-CZE: abstract-CZE,
  abstract-ENG: abstract-ENG,
  keywords-CZE: "TODO",
  keywords-ENG: "TODO",
  thesis-type: "bachelor",
  lang: "english",
  twosided: false,
)

#let err-color = red.lighten(60%)
#let ok-color = green.lighten(60%)
#let holds-color = green.lighten(40%)
#let not-color = red.lighten(40%)
#let unknown-color = yellow.lighten(18%)

// #let impl(name) = {
//   // font: https://github.com/typst/typst/pull/6000
//   // set text(font: "DejaVu Sans Mono")
//   box(
//     baseline: 25%,
//     inset: 0.3em,
//     fill: blue.lighten(80%),
//     radius: 0.32em, // consistent with codly
//     text(size: 0.88em, name)
//   )
//   h(0.25em)
// }
// #let clause(state, name) = {
//   box(
//     baseline: 25%,
//     // inset: 0.34em,
//     inset: 0.3em,
//     fill: state,
//     radius: 0.32em, // consistent with codly
//     text(size: 0.88em, name)
//     // name
//   )
// }
// #let clauses(..pairs) = {
//   // set text(size: 0.885em)
//   for (state, name) in pairs.pos() {
//     clause(state, name)
//     h(0.25em)
//   }
// }

= CUDA, GPU computations

// short intro 

= Introduction to TNL


// == PyTorch, TensorFlow??

= Higher order functions and just-in-time compilation

== TNL Functions

== PyTNL and Nanobind

== Numba <numba_introduction>

== NVRTC

== Benchmark <function_calling_from_cpp_benchmark>

== Other Python libraries

=== CuPy

=== Polars

// https://docs.pola.rs/user-guide/expressions/user-defined-python-functions/#processing-a-whole-series-with-map_batches

=== NumPy

=== JAX


= Accessing #cpp  \ managed memory

As calling and executing functions defined in Python from #cpp seem to be either unpractical or unbearably slow, it was time to explore different options. With the goal being finding a way to allow custom modification of data held in TNL data structures, it's possible to invert the flow from Python to #cpp. 

Instead of passing and binding the Python functions to the #cpp side of the code, we can expose the data structures in way where we could natively run the user defined functions on them right from Python. As the benchmark suggests the biggest slowdown occurred in the crossings of the language boundaries.

Inverting the flow this way may eliminate this transfer as instead of passing each element, the TNL data structure will produce an interface that allows direct access to the underlying data in the memory. The consumer can read and even modify the data in place with no further need to call the PyTNL bindings or TNL functions. 

Following three protocols described here were chosen for two primary reasons. Firstly Numba library described in @numba_introduction, or it's Numba-cuda counterpart, offers out of the box support for them. Numba JIT compiled functions can natively consume the interfaces with a relatively pleasant user experience as I will try to demonstrate later in the chapter.

// https://data-apis.org/array-api/2025.12/design_topics/data_interchange.html#dlpack-an-in-memory-tensor-structure
Secondly, all interfaces mentioned here come recommended in the Python Array API Standard for data transfers between different libraries and as such are likely to be most adopted in the Python ecosystem.


== Python Array API Standard

// https://data-apis.org/array-api/2025.12/design_topics/data_interchange.html#dlpack-an-in-memory-tensor-structure
// https://data-apis.org/array-api/2025.12/purpose_and_scope.html

Python ecosystem currently offers many libraries that offer implementations of multidimensional arrays. Examples include already mentioned NumPy, Polars and CuPy but also libraries more focused like Pytorch or Tenserflow for deep learning. Most importantly, TNL and it's `NDArray` fits right in as well.

While the interfaces often share similarities, as they are frequently inspired by NumPy, the historical standard for numerical computing in Python, their subtle inconsistencies make it difficult to write portable code that can seamlessly operate across multiple libraries.

Python Array API Standard, whose first version released in 2021, attempts to address this growing fragmentation. The authors' goals however is by no means to make the libraries identical or make them all conform the the NumPy's API. Quite opposite in fact, they openly recognize there are good reasons for the inconsistencies and differences. They specifically list non-CPU device or JIT compilers support as some of the reasons the standard is willing to deviate from the laid ground work by these long existing libraries.

That, in my opinion, makes the standard highly relevant both to this work and PyTNL itself. Apart from lowering user§s learning curve by making the API more familiar. Adhering to the the standard would allows array-consuming libraries, like Numba, to accept PyTNL array-like data structures and run operations on them directly.

// https://data-apis.org/array-api/2025.12/design_topics/data_interchange.html
The interoperability can be achieved either by Python's duck typing, or, more importantly, through a data exchange mechanism that would allow converting the arrays into others or simply directly accessing the underlying data. Instead of designing it's own protocol, the standard states requirements the protocol should fulfil and recommends an already existing protocol, along with two possible alternatives. All three protocols are described below.

I list the requirements in @array_standard_interchange_requirements_table. For our use case, that is allowing Numba's JIT compiled functions to execute upon the PyTNL's array, the most important requirement is allowing the zero-copy view. Forcing a copy, be it inside the same memory block or worse, from one device memory to another, would likely once again invalidate all the performance gains the function compilation provides in the first place.

It's of course similarly important to offer multi device support, as the (Py)TNL is built with device support in mind as well. However, this requirement can be be easily circumvented by simply supporting multiple different protocols. 


// https://data-apis.org/array-api/2025.12/design_topics/data_interchange.html
#figure(
  table(
    columns: (auto, 1fr),
    // stroke: none,
    // gutter: 0.8em,
    inset: (x: 8pt, y: 12pt),
    
    // Academic Header
    table.header(
      // table.hline(stroke: 1.5pt),
      [*Component*], [*Requirement and Rationale*],
      // table.hline(stroke: 0.5pt),
    ),
    
    // Row 1
    [*Memory Layout*], [
      Data access via a protocol that describes the memory layout of the array in an implementation-independent manner.
      
      #set text(size: 0.9em, style: "italic")
      Rationale: any number of libraries must be able to exchange data, and no particular package must be needed to do so.
    ],

    // Row 2
    [*Dtypes*], [
      Support for all dtypes in this API standard (see Data Types).
    ],

    // Row 3
    [*Device Support*], [
      Device support. It must be possible to determine on what device the array that is to be converted lives.
      
      #set text(size: 0.9em, style: "italic")
      Rationale: there are CPU-only, GPU-only, and multi-device array types; it’s best to support these with a single protocol (with separate per-device protocols it’s hard to figure out unambiguous rules for which protocol gets used, and the situation will get more complex over time as TPU’s and other accelerators become more widely available).
    ],

    // Row 4
    [*Zero-copy*], [
      Zero-copy semantics where possible, making a copy only if needed (e.g. when data is not contiguous in memory).
      
      #set text(size: 0.9em, style: "italic")
      Rationale: performance.
    ],

    // Row 5
    [*Interfaces*], [
      A Python-side and a C-side interface, the latter with a stable C ABI.
      
      #set text(size: 0.9em, style: "italic")
      Rationale: all prominent existing array libraries are implemented in C/C++, and are released independently from each other. Hence a stable C ABI is required for packages to work well together.
    ],
    
    table.hline(stroke: 1.5pt),
  ),
  caption: [Array API interchange protocol requirements and rationales.],
) <array_standard_interchange_requirements_table>

== Python Buffer protocol

// https://peps.python.org/pep-3118/
// https://docs.python.org/3/c-api/buffer.html#bufferobjects
The modern Python Buffer protocol was introduced via PEP 3118 alongside the transition to Python 3. It was designed to resolve limitations in the older buffer API by adding support for multi-dimensional, non-contiguous arrays and complex data types. Its primary goal is to provide a standardized C-level API that allows different Python objects and native extensions—such as NumPy, PIL, or the standard library's io module—to safely share memory and exchange data without the overhead of copying.

At its core, the protocol revolves around the `Py_buffer` C structure. When a consumer wishes to access the underlying memory of a buffer-providing object (the producer), it calls the `PyObject_GetBuffer` function. The producer then populates the `Py_buffer` structure with a pointer to the raw data block (buf) alongside rich metadata necessary to interpret the layout. This metadata includes the data type (format), item size, shape, strides for non-contiguous memory access, and a flag indicating whether the memory is read-only.

A critical limitation of the Buffer protocol, particularly in the context of modern heterogeneous computing, is its strict assumption that the underlying data resides in CPU-accessible system memory (host memory). The protocol provides no mechanisms, flags, or semantics for denoting device memory, such as data residing on a GPU or other hardware accelerators. The pointer exposed by the protocol is expected to be directly dereferenceable by the host CPU. This fundamental restriction is what necessitated the creation of alternative standards—such as the CUDA Array interface described in a subsequent section—to handle device-side data sharing.

// https://peps.python.org/pep-0688/
While historically restricted to C extensions, recent developments via PEP 688 (implemented in Python 3.12) have formally exposed the protocol to purely Python-side code. Python classes can now participate as producers by implementing the `__buffer__` and `__release_buffer__` special methods. On the consumer side, Python code natively interacts with the protocol via the built-in memoryview object, providing a safe abstraction over the raw memory buffer.

In terms of memory management and object lifetime, the Buffer protocol enforces a strict lock-and-release mechanism. When a consumer requests a buffer view, the producer is notified and typically increments its reference count or locks the underlying memory to prevent reallocation or destruction. Because of this handshake, the consumer is explicitly obligated to call `PyBuffer_Release` (or trigger `__release_buffer__` on the Python side) once it is finished with the view. This ensures highly safe zero-copy data sharing, as the original producer precisely tracks when the exported memory is no longer in use and can safely unlock or free the resources.


== CUDA Array interface

// https://numba.pydata.org/numba-doc/0.43.0/cuda/cuda_array_interface.html?highlight=cuda%20array%20interface
// https://nvidia.github.io/numba-cuda/user/cuda_array_interface.html
// the actual first release
// https://numba.pydata.org/numba-doc/0.39.0/release-notes.html?highlight=release%20notes
CUDA Array interface has been first proposed an implemented by the Numba package in 2018. It allowed Numba to consume any external arrays that provide this interface. The aim however was to propose a solution not only enabling compatibility for Numba, but even in between different packages among themselves. Inspired by NumPy Array inteface it aims to allow interoperability between CUDA array-like objects in all projects.

The specification itself is rather simple, especially as, compared to the Buffer protocol or the above mentioned NumPy Array interface, it defined only Python-side access. C-side access is still said to only be considered for the future.

As such, the interface defines only a single attribute that should be accessible on the array-like objects named `__cuda_array_interface__`.  It must return a regular Python dictionary with fields described in @cai_fields. 

The consumer simply accesses the underlying buffer by the supplied pointer in the `data` field. Rest of the dictionary should provide all the necessary metadata such as element's `datatype`, `shape`, and others to allow the consumer to work with the data as it sees fit.

Note that while this allows creation of zero copy views of the data, the interface does not handle ownership transfer or even object's lifetime in any way. The original producer generally remains responsible for the data and their eventual destruction.

The user is also responsible for ensuring the original object's lifetime outlives the view. Some libraries may help the user with this by keeping the reference to the original object. That is however library dependant and is not specified in the standard.

// https://docs.cupy.dev/en/stable/reference/generated/cupy.asarray.html#cupy.asarray
For example, CuPy holds the reference after construting the object with `asarray` function only if the original has been a CuPy array as well. Numba itself provides two different options for constructing the view. One holds the reference, the other does not.

#figure(
  table(
    columns: (auto, auto, auto),
    align: (left, center, left),
    // fill: (_, row) => if row == 0 { luma(240) } else { none },
    table.header(
      [*Field*], [*Required*], [*Description*]
    ),
    [`shape`], [Yes], [A tuple of integers representing the size of each dimension.],
    [`typestr`], [Yes], [The type string. This shares the same definition as `typestr` in the NumPy array interface.],
    [`data`], [Yes], [A 2-tuple where the first element is the device-accessible data pointer (as a Python integer) and the second is a boolean read-only flag.],
    [`version`], [Yes], [An integer indicating the version of the interface being exported (the current version is 3).],
    [`strides`], [No], [A tuple of integers representing the number of bytes to skip to access the next element at each dimension. If `None` or omitted, the array is assumed to be in C-contiguous layout.],
    [`descr`], [No], [Used to describe more complicated types, following the same specification as in the NumPy array interface.],
    [`mask`], [No], [`None` or an object exposing the `__cuda_array_interface__` that acts as a mask, indicating which elements of the array are valid.],
    [`stream`], [No], [`None` or an integer representing a stream upon which synchronization must take place at the point of consumption.]
  ),
  caption: [A summary of the dictionary fields defined in the Python interface specification of `__cuda_array_interface__`.]
)<cai_fields>

== DLPack

// https://data-apis.org/array-api/2025.12/design_topics/data_interchange.html#dlpack-an-in-memory-tensor-structure
// https://dmlc.github.io/dlpack/latest/
As demonstrated in the previous sections, both the Buffer protocol and the CUDA Array interface have significant limitations when considered as a universal standard for heterogeneous computing. The Buffer protocol is strictly confined to CPU-accessible host memory, while the CUDA Array interface is specifically designed for GPU memory and lacks a standardized mechanism for memory management and object lifetime. To address these exact shortcomings, the Python Array API Standard explicitly recommends DLPack as the primary data interchange protocol.

DLPack is an open, in-memory tensor structure designed specifically to facilitate the sharing of tensors across different hardware devices and frameworks. Unlike its predecessors, DLPack fulfills all the strict requirements established by the Array API Standard (as outlined in @array_standard_interchange_requirements_table). It provides a stable C ABI, allows for zero-copy semantics, and comprehensively supports a wide array of hardware devices, including CPUs, CUDA GPUs, ROCm, OpenCL, and Vulkan, among others.

At the C-level, the specification revolves around two primary structures: DLTensor and DLManagedTensor. The DLTensor structure contains the actual pointer to the data array alongside all the necessary metadata to interpret it, such as the target device, data type, shape, and strides. I summarize the fields of the DLTensor structure in @dlpack_fields.

To resolve the ownership and lifetime ambiguities present in protocols like the CUDA Array interface, DLPack relies on the DLManagedTensor structure. This struct acts as a wrapper around the DLTensor, adding a manager_ctx pointer and, crucially, a deleter function. When a producer exports an array, it provides this deleter callback. Once the consumer is finished utilizing the zero-copy view, it is explicitly obligated to call the deleter. This mechanism ensures that the original producer is safely notified to release or free the underlying memory without requiring the user to manually manage Python object references.

// https://dmlc.github.io/dlpack/latest/_images/DLPack_diagram.png
#figure(
  image("assets/DLPack_diagram.png", width: 85%),
  caption: [Visual representation of the DLPack data structures, illustrating the relationship between the tensor metadata and the managed memory context.]
) <dlpack_architecture_diagram>

// https://dmlc.github.io/dlpack/latest/python_spec.html
On the Python side, DLPack is implemented through a standardized interface consisting of two special methods that producer objects must expose: `__dlpack_device__` and `__dlpack__`.

The `__dlpack_device__(self)` method returns a two-element tuple containing the device type (represented as an integer enum) and the device ID. This allows a consumer to inspect where the data resides before attempting to construct a view or perform operations, enabling it to raise an error early if the target device is unsupported.

The `__dlpack__(self, *, stream=None)` method handles the actual data exchange. When called, the producer allocates a DLManagedTensor C structure, populates it with the array's data and metadata, and wraps it in a standard Python PyCapsule object named "dltensor". This capsule safely transports the C-level struct across the Python boundary. The consumer then unpacks the capsule, accesses the raw data, and assumes responsibility for calling the provided deleter when the capsule is consumed or destroyed. Furthermore, the optional stream argument allows frameworks to synchronize asynchronous hardware operations (like CUDA streams) during the handoff, ensuring data integrity during the exchange.

#figure(
table(
columns: (auto, auto),
align: (left, left),
// fill: (_, row) => if row == 0 { luma(240) } else { none },
table.header(
[Field], [Description]
),
[data], [An opaque pointer to the raw memory containing the tensor elements.],
[device], [A DLDevice structure detailing the device type (e.g., CPU, CUDA, OpenCL) and the specific device index.],
[ndim], [An integer indicating the number of dimensions in the tensor.],
[dtype], [A DLDataType structure defining the type code (e.g., integer, float, bfloat), the number of bits, and the number of lanes (for vector types).],
[shape], [A pointer to an array of integers representing the size of the tensor in each of its ndim dimensions.],
[strides], [A pointer to an array of integers indicating the number of elements to skip in memory to reach the next element along each dimension. Can be NULL if the tensor is compact and contiguous.],
[byte_offset], [An integer specifying the byte offset from the data pointer to the actual beginning of the tensor data.]
),
caption: [A summary of the fields defined within the DLTensor C structure.]
)<dlpack_fields>



== Unlocked possibilities and usage

...

The goal of my implementation could be split into three parts.

+ Allow zero copy views of PyTNL containers in compatible libraries.
+ Allow executing JIT compiled functions and kernels directly on PyTNL containers.
+ Explore the unlocked possibilities for the non array data structures like sparse matrices.
+ Evaluate the performance of custom element wise operations using the direct access through the protocols and compare with the results from @function_calling_from_cpp_benchmark. 



To fulfil the first goal, user should be able to construct, fill a PyTNL array 

```python
@jit(nopython=True)
def fill_with_index_njit(data):
    """Fill a 1D array with values matching their indices."""
    for i in range(len(data)):
        data[i] = i


@vectorize(["float64(float64, float64)"], nopython=True)
def vectorized_scale(x, scale):
    """Element-wise scale implemented through Numba vectorize (CPU)."""
    return x * scale


@cuda.jit
def numba_scale_kernel_3d(data, scale, nx, ny, nz):
    """Scale a 3D NDArray element-wise."""
    i, j, k = cuda.grid(3)
    if i < nx and j < ny and k < nz:
        data[i, j, k] = data[i, j, k] * scale
```

...

== Implementation

// https://gitlab.com/tnl-project/pytnl/-/commit/4db8e9e15c3a32fa260f369899d542cb57fc71e6
Luckily for me, PyTNL already implemented the DLPack protocol prior to this work. In fact, it supports ever since it implemented the bindings of arrays based in the CUDA devices. 

// TODO: Finish xd
...

// https://github.com/numba/numba/issues/4719
// https://github.com/NVIDIA/numba-cuda/issues/122
While, as discussed above, the DLPack pretty surpasses both the Buffer Protocol and the CUDA Array interface, to allow all of the use cases described above, I had to implement both of these protocols either way. Numba, the library I am testing the JIT compilation against, simply did not support the DLPack yet when I started exploring the options. 

DLPack support is and has been a long planned feature both in Numba itself and it's `numba-cuda` module. Interestingly enough, the cuda module finally allowed consuming arrays through the dlpack just this march. 

Since that development, there's only little to no benefits for maintaining support for the CAI. Python Buffer protocol is still needed however because it still offers the only way to consume CPU hosted arrays by the main Numba JIT.

// https://gitlab.com/tnl-project/pytnl/-/merge_requests/74
// https://gitlab.com/tnl-project/pytnl/-/merge_requests/73
As such, only the Buffer protocol support has been merged into PyTNL itself in the end.

There's not really much to say about the implementation itself. It's mostly just filling the exported structs with the proper data which is luckily readily available in the PyTNL containers. Maybe interesting bit is the fact that the buffer protocol is implemented through a Python C API slots as it doesn't have any Python side interface. 



= Demonstration

== PDLP Solver

== SPH???????

= Julia ?

== Bindings libraries

== C like performance

== JIT 


// = Theory

// == TNL

// === Data structures

// === Higher-order functions

// == PyTNL

// === Capabilities, what I am going to handle 

// == Python Buffer Protocol

// == Cuda array interface

// == 

// = Lambda functions at the \ language barrier

// PyTNL as a Python interface for TNL library provides bindings for the original #cpp code. 

// = Dynamic compiling of lambda functions

// intro

// == Lambda functions in TNL

// TNL exposes several useful higher order functions that extends users options for modifying the TNl data structures using their own lambda functions. Thanks to context capturing and working with #cpp iterators, they provide a fairly powerful API. One such example might be the `ParallelFor` function.

// === #cpp lambda functions

// // TODO: quick c++ overview of lambda functions

// === Python lambda functions

// // TODO: quick python lambda function overview

// == Nanobind

// === Type casting std::function

// === Wrapping nb::callable



// === Utilizing python lambda functions in PyTNL

// The goal is reasonably simple from the API perspective. PyTNL should allow users to write some kind of lambda functions and allow executing them upon PyTNL exposed data structures. Ideally we would expose already existing higher order functions from TNL.

// The main challenge of binding a higher order function such as `ParallelFor` is the ability to pass a Python Lambda function into 

// Binding a higher order function such as `ParallelFor` faces two big challenges:

// + Passing a Python Lambda function into the #cpp codebase and executing it from there.
// + Allowing the context capture. As above, we would be capturing Python objects and subsequently passing them once again into the #cpp runtime. 



// == Tools


// === Numba

// To battle the performance issues of Python code, I tried to explore JIT compilation options. If we could precompile the python lambdas and separate it from the interpreter, we could achieve significant speed increase. 
// // TODO some source showing JIT in Numba actually speeds something up.

// However, even JIT Numba precompiled functions are still passed through the bindings as a Python object and is still pretty slow.

// I had to eliminate Python all together and that was possible with numbas Cfuncs. The bindings had to be adjusted to accept a pointer straight to the function instead of `nb::callable`. This truly did speed things up. However two problems remained. Context capture sucked and even more so, this function could only be executed by the CPU. In order to run the code on device, we would need a differently compiled kernel.

// === Numba CUDA

// And that's where Numba CUDA was supposed to come in. However, I quickly discovered cuda has no cfunc equivalent. And Numba CUDA functions could not be passed by pointers to the bindings.
// // TODO: What about nb::callable???

// === Cupy, Cuda CORE - NRVTC

