#import "ctufit-thesis.typ": *
#let cpp = box[C#h(-0.1em)++\u{2060}]

= Accessing #cpp \ managed memory <accessing_cpp_managed_memory_heading>

The previous chapter demonstrated that calling Python functions from #cpp is either impractical or prohibitively slow. These findings motivated the exploration of an alternative approach: rather than passing Python callbacks into the #cpp runtime, the data structures themselves can be exposed in a way that allows user-defined functions to operate on them directly from Python. As the benchmark in @function_calling_from_cpp_benchmark suggests, the dominant performance bottleneck lies in the repeated crossings of the language boundary, so eliminating those crossings is the primary objective.

To this end, the approach taken in this chapter inverts the control flow. Instead of the #cpp side invoking a user-supplied function for each element, a TNL data structure produces an interface that grants direct access to its underlying memory. The consumer can then read and modify the data in place, with no further need to invoke the PyTNL bindings or TNL functions during the computation itself. The language boundary is crossed only once --- when the memory view is exported --- rather than on every element access.

// https://data-apis.org/array-api/2025.12/design_topics/data_interchange.html#dlpack-an-in-memory-tensor-structure
The three data interchange protocols described in this chapter were selected for two reasons. First, the Numba library introduced in @numba_introduction, as well as its CUDA counterpart, provides out-of-the-box support for consuming them. Numba JIT-compiled functions can natively operate on the exported interfaces, yielding a convenient user experience that is demonstrated later in the chapter. Second, all three protocols are recommended by the Python Array API Standard as the preferred mechanisms for data exchange between libraries, making them the most widely adopted conventions in the Python scientific ecosystem. #cite(<c_array-api-standard>)


== Python Array API Standard

Python ecosystem currently offers many libraries that offer implementations of multidimensional arrays. Examples include already mentioned NumPy, Polars and CuPy but also libraries more focused like Pytorch or TensorFlow for deep learning. Most importantly, PyTNL and its `NDArray` fits right in as well.

While the interfaces often share similarities, as they are frequently inspired by NumPy, the historical standard for numerical computing in Python, their subtle inconsistencies make it difficult to write portable code that can seamlessly operate across multiple libraries.

// https://data-apis.org/array-api/2025.12/design_topics/data_interchange.html#dlpack-an-in-memory-tensor-structure
// https://data-apis.org/array-api/2025.12/purpose_and_scope.html
Python Array API Standard, whose first version released in 2021, attempts to address this growing fragmentation. The authors' goals however is by no means to make the libraries identical or make them all conform to the NumPy's API. Quite opposite in fact, they openly recognize there are good reasons for the inconsistencies and differences. They specifically list non-CPU device or JIT compilers support as some of the reasons the standard is willing to deviate from the laid ground work by these long existing libraries. #cite(<c_array-api-standard>)

That makes the standard highly relevant both to this work and PyTNL itself. Apart from lowering user's learning curve by making the API more familiar. Adhering to the the standard would allows array-consuming libraries, like Numba, to accept PyTNL array-like data structures and run operations on them directly, bringing the interoperability to the level of other libraries. 

// https://data-apis.org/array-api/2025.12/design_topics/data_interchange.html
It can be achieved either by Python's duck typing, or, more importantly, through a data exchange mechanism that would allow converting between different array implementations by exposing the underlying data directly. Instead of designing its own protocol, the standard states requirements(@array_standard_interchange_requirements_table) the protocol should fulfil and recommends an already existing protocol, along with two possible alternatives. All three protocols are described below.

To allow Numba's JIT compiled functions to execute on top of the PyTNL's array, the most important requirement is allowing the zero-copy view. Forcing a copy, be it inside the same memory block or worse, from one device memory to another, would likely once again invalidate all the performance gains the function compilation provides in the first place.

It is of course similarly important to offer multi device support, as the (Py)TNL is built with device support in mind as well. However, this requirement can be be easily circumvented by simply supporting multiple different protocols.


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
    [*Memory Layout*],
    [
      Data access via a protocol that describes the memory layout of the array in an implementation-independent manner.

      #set text(size: 0.9em, style: "italic")
      Rationale: any number of libraries must be able to exchange data, and no particular package must be needed to do so.
    ],

    // Row 2
    [*Dtypes*],
    [
      Support for all dtypes in this API standard (see Data Types).
    ],

    // Row 3
    [*Device Support*],
    [
      Device support. It must be possible to determine on what device the array that is to be converted lives.

      #set text(size: 0.9em, style: "italic")
      Rationale: there are CPU-only, GPU-only, and multi-device array types; it’s best to support these with a single protocol (with separate per-device protocols it’s hard to figure out unambiguous rules for which protocol gets used, and the situation will get more complex over time as TPU’s and other accelerators become more widely available).
    ],

    // Row 4
    [*Zero-copy*],
    [
      Zero-copy semantics where possible, making a copy only if needed (e.g. when data is not contiguous in memory).

      #set text(size: 0.9em, style: "italic")
      Rationale: performance.
    ],

    // Row 5
    [*Interfaces*],
    [
      A Python-side and a C-side interface, the latter with a stable C ABI.

      #set text(size: 0.9em, style: "italic")
      Rationale: all prominent existing array libraries are implemented in C/C++, and are released independently from each other. Hence a stable C ABI is required for packages to work well together.
    ],

    table.hline(stroke: 1.5pt),
  ),
  caption: [Array API interchange protocol requirements and rationales. #cite(<c_array-api-standard>)],
) <array_standard_interchange_requirements_table>

== Python Buffer protocol

// https://peps.python.org/pep-3118/
// https://docs.python.org/3/c-api/buffer.html#bufferobjects
The modern Python Buffer protocol was introduced via PEP 3118 along with the transition to Python 3. It was designed to resolve limitations in the older buffer API by adding support for multi-dimensional, non-contiguous arrays and complex data types. Its primary goal is to provide a standardized C-level API that allows different Python objects and native extensions—such as NumPy, PIL, or the standard library's io module—to safely share memory and exchange data without the copying overhead. #mcite(<c_pep3118>, <c_python-buffer-api>)

At its core, the protocol revolves around the `Py_buffer` C structure. When a consumer wishes to access the underlying memory of a buffer-providing object (the producer), it calls the `PyObject_GetBuffer` function. The producer then populates the `Py_buffer` structure with a pointer to the raw data block (buf) alongside rich metadata necessary to interpret the layout. This metadata includes the data type, item size, shape, strides and a flag indicating whether the memory is read-only.

// TODO: Field diagram of Py_buffer struct
// TODO: Describe the strides in more detail
// TODO: Describe the Suboffsets field and how it allows for non-contiguous arrays

A critical limitation of the Buffer protocol, particularly in the context of modern heterogeneous computing, is its strict assumption that the underlying data resides in CPU-accessible system memory (host memory). The protocol provides no mechanisms, flags, or semantics for denoting device memory, such as data residing on a GPU or other hardware accelerators. The pointer exposed by the protocol is expected to be directly dereferenceable by the host CPU. This fundamental restriction is what necessitated the creation of alternative standards—such as the CUDA Array interface described in a subsequent section—to handle device-side data sharing.

// https://peps.python.org/pep-0688/
While historically restricted to C extensions, recent developments via PEP 688 (implemented in Python 3.12) have formally exposed the protocol to purely Python-side code. Python classes can now participate as producers by implementing the `__buffer__` and `__release_buffer__` special methods. On the consumer side, Python code natively interacts with the protocol via the built-in memoryview object, providing a safe abstraction over the raw memory buffer. #cite(<c_pep688>)

In terms of memory management and object lifetime, the Buffer protocol enforces a strict lock-and-release mechanism. When a consumer requests a buffer view, the producer is notified and typically increments its reference count or locks the underlying memory to prevent reallocation or destruction. Because of this handshake, the consumer is explicitly obligated to call `PyBuffer_Release` (or trigger `__release_buffer__` on the Python side) once it is finished with the view. This ensures highly safe zero-copy data sharing, as the original producer precisely tracks when the exported memory is no longer in use and can safely unlock or free the resources.


== CUDA Array interface

// https://numba.pydata.org/numba-doc/0.43.0/cuda/cuda_array_interface.html
// https://nvidia.github.io/numba-cuda/user/cuda_array_interface.html
// https://numba.pydata.org/numba-doc/0.39.0/release-notes.html
CUDA Array interface has been first proposed and implemented by the Numba package in 2018. It allowed Numba to consume any external arrays that provide this interface. The aim however was greater. Inspired by NumPy Array interface it aims to allow interoperability between CUDA array-like objects in all projects. #mcite(<c_cuda-array-interface>, <c_numba039-release>)

The specification itself is rather simple, especially as, compared to the Buffer protocol or the above mentioned NumPy Array interface. It defines only Python-side access. Although C-side access is said to be considered for the future.

// TODO: Make sure the field descriptions are more coherent

As such, the interface defines only a single attribute that should be accessible on the array-like objects named `__cuda_array_interface__`.  It must return a regular Python dictionary populated with fields described in @cai_fields.

The consumer simply accesses the underlying buffer by the supplied pointer in the `data` field. Rest of the dictionary should provide all the necessary metadata such as element's `datatype`, `shape`, and others to allow the consumer to work with the data as it sees fit.

Note that while this allows creation of zero copy views of the data, the interface does not handle ownership transfer or even object's lifetime in any way. The original producer generally remains responsible for the data and their eventual destruction.

The user is also responsible for ensuring the original object's lifetime outlives the view. Some libraries may help the user with this by keeping the reference to the original object. That is however library dependent and is not specified in the standard.

// https://docs.cupy.dev/en/stable/reference/generated/cupy.asarray.html
For example, CuPy holds the reference after constructing the object with `asarray` function only if the original has been a CuPy array as well. Numba itself provides two different options for constructing the view. One holds the reference, the other does not. #cite(<c_cupy-asarray>)

#figure(
  table(
    columns: (auto, auto, auto),
    align: (left, center, left),
    // fill: (_, row) => if row == 0 { luma(240) } else { none },
    table.header([*Field*], [*Required*], [*Description*]),
    [`shape`], [Yes], [A tuple of integers representing the size of each dimension.],
    [`typestr`], [Yes], [The type string. This shares the same definition as `typestr` in the NumPy array interface.],
    [`data`],
    [Yes],
    [A 2-tuple where the first element is the device-accessible data pointer (as a Python integer) and the second is a boolean read-only flag.],

    [`version`], [Yes], [An integer indicating the version of the interface being exported (the current version is 3).],
    [`strides`],
    [No],
    [A tuple of integers representing the number of bytes to skip to access the next element at each dimension. If `None` or omitted, the array is assumed to be in C-contiguous layout.],

    [`descr`],
    [No],
    [Used to describe more complicated types, following the same specification as in the NumPy array interface.],

    [`mask`],
    [No],
    [`None` or an object exposing the `__cuda_array_interface__` that acts as a mask, indicating which elements of the array are valid.],

    [`stream`],
    [No],
    [`None` or an integer representing a stream upon which synchronization must take place at the point of consumption.],
  ),
  caption: [A summary of the dictionary fields defined in the Python interface specification of `__cuda_array_interface__`.],
)<cai_fields>

== DLPack

// https://data-apis.org/array-api/2025.12/design_topics/data_interchange.html#dlpack-an-in-memory-tensor-structure
// https://dmlc.github.io/dlpack/latest/
// https://data-apis.org/array-api/2025.12/design_topics/data_interchange.html#dlpack-an-in-memory-tensor-structure
// https://dmlc.github.io/dlpack/latest/
As demonstrated in the previous sections, both the Buffer protocol and the CUDA Array interface have significant limitations when considered as a universal standard for heterogeneous computing. The Buffer protocol is strictly confined to CPU-accessible host memory, while the CUDA Array interface is specifically designed for GPU memory and lacks a standardized mechanism for memory management and object lifetime. To address these exact shortcomings, the Python Array API Standard explicitly recommends DLPack as the primary data interchange protocol. #mcite(<c_array-api-standard>, <c_dlpack>)

DLPack is an open, in-memory tensor structure designed specifically to facilitate the sharing of tensors across different hardware devices and frameworks. Unlike its predecessors, DLPack fulfills all the strict requirements established by the Array API Standard (as outlined in @array_standard_interchange_requirements_table). It provides a stable C ABI, allows for zero-copy semantics, and comprehensively supports a wide array of hardware devices, including CPUs, CUDA GPUs, ROCm, OpenCL, and Vulkan.

At the C-level, the specification revolves around two primary structures: DLTensor and DLManagedTensor. The DLTensor structure contains the actual pointer to the data array alongside all the necessary metadata to interpret it, such as the target device, data type, shape, and strides. The fields of the DLTensor structure are summarized in @dlpack_fields.

// TODO: maybe the diagram makes the table redundant, remove?

To resolve the ownership and lifetime ambiguities present in protocols like the CUDA Array interface, DLPack relies on the DLManagedTensor structure. This struct acts as a wrapper around the DLTensor, adding a further metadata and, crucially, a deleter function. When a producer exports an array, it provides this deleter callback. Once the consumer is finished utilizing the zero-copy view, it is explicitly obligated to call the deleter. This mechanism ensures that the original producer is safely notified to release or free the underlying memory without requiring the user to manually manage Python object references.

// https://dmlc.github.io/dlpack/latest/_images/DLPack_diagram.png
// https://dmlc.github.io/dlpack/latest/_images/DLPack_diagram.png
#figure(
  image("assets/DLPack_diagram.png", width: 85%),
  caption: [Visual representation of the DLPack data structures, illustrating the relationship between the tensor metadata and the managed memory context.],
) <dlpack_architecture_diagram>

// https://dmlc.github.io/dlpack/latest/python_spec.html
On the Python side, DLPack is implemented through a standardized interface consisting of two special methods that producer objects must expose: `__dlpack_device__` and `__dlpack__`. #cite(<c_dlpack-python-spec>)

The `__dlpack_device__(self)` method returns a two-element tuple containing the device type (represented as an integer enum) and the device ID. This allows a consumer to inspect where the data resides before attempting to construct a view or perform operations, enabling it to raise an error early if the target device is unsupported.

The `__dlpack__(self, *, stream=None)` method handles the actual data exchange. When called, the producer allocates a DLManagedTensor C structure, populates it with the array's data and metadata, and wraps it in a standard Python PyCapsule object named "dltensor". This capsule safely transports the C-level struct across the Python boundary. The consumer then unpacks the capsule, accesses the raw data, and assumes responsibility for calling the provided deleter when the capsule is consumed or destroyed. Furthermore, the optional stream argument allows frameworks to synchronize asynchronous hardware operations (like CUDA streams) during the handoff, ensuring data integrity during the exchange.

#figure(
  table(
    columns: (auto, auto),
    align: (left, left),
    // fill: (_, row) => if row == 0 { luma(240) } else { none },
    table.header([Field], [Description]),
    [data], [An opaque pointer to the raw memory containing the tensor elements.],
    [device], [A DLDevice structure detailing the device type (e.g., CPU, CUDA, OpenCL) and the specific device index.],
    [ndim], [An integer indicating the number of dimensions in the tensor.],
    [dtype],
    [A DLDataType structure defining the type code (e.g., integer, float, bfloat), the number of bits, and the number of lanes (for vector types).],

    [shape], [A pointer to an array of integers representing the size of the tensor in each of its ndim dimensions.],
    [strides],
    [A pointer to an array of integers indicating the number of elements to skip in memory to reach the next element along each dimension. Can be NULL if the tensor is compact and contiguous.],

    [byte_offset],
    [An integer specifying the byte offset from the data pointer to the actual beginning of the tensor data.],
  ),
  caption: [A summary of the fields defined within the DLTensor C structure.],
)<dlpack_fields>



== Implementation <protocol_implementation>

The following subsections describe the work undertaken to add Buffer protocol and CUDA Array interface support to PyTNL, the constraints that shaped the final design, and the resulting state of the codebase.

=== Prior state of DLPack support

// https://gitlab.com/tnl-project/pytnl/-/commit/4db8e9e15c3a32fa260f369899d542cb57fc71e6
Prior to this work, PyTNL already provided an implementation of the DLPack protocol. DLPack support was introduced alongside the original CUDA device bindings for PyTNL's array types, as DLPack was the primary mechanism through which other Python libraries could consume GPU-resident arrays. Consequently, implementing DLPack from scratch was not within the scope of this thesis, and the existing implementation served as a foundation upon which the remaining protocols were built. #cite(<c_pytnl-dlpack-commit>)

// https://github.com/numba/numba/issues/4719
// https://github.com/NVIDIA/numba-cuda/issues/122
Although DLPack is the recommended interchange protocol and satisfies all the requirements set by the Python Array API standard (@array_standard_interchange_requirements_table), its adoption among consumer libraries was not yet complete at the time this work began. Numba, the primary JIT compilation framework used for evaluation in this thesis (introduced in @numba_introduction), did not support consuming arrays through DLPack in either its CPU or CUDA backends. DLPack reading had been a long-planned feature in both the core Numba project and its `numba-cuda` module, but neither had shipped an implementation. #mcite(<c_numba-dlpack-issue>, <c_numba-cuda-dlpack-issue>)

This limitation necessitated implementing the two remaining protocols. The Python Buffer protocol was required to enable Numba's CPU-side JIT compiler (`@jit`, `@vectorize`) to operate on PyTNL arrays residing in host memory. The CUDA Array interface was required to enable Numba's CUDA backend (`@cuda.jit`) to launch kernels directly on PyTNL arrays residing in device memory.

=== Evolution during development

// https://github.com/NVIDIA/numba-cuda/pull/790
// https://github.com/NVIDIA/numba-cuda/releases/tag/v0.28.1
The landscape shifted during the course of this work. The `numba-cuda` project merged support for consuming DLPack tensors in March 2026, which rendered the CUDA Array interface implementation redundant for the Numba use case. With DLPack already present in PyTNL and now consumable by `numba-cuda`, the CUDA Array interface no longer provided a unique capability. #mcite(<c_numba-cuda-dlpack-pr>, <c_numba-cuda-v0281>)

The CPU-side Numba JIT, however, still does not support DLPack as an input mechanism. The Python Buffer protocol therefore remains the only viable path for enabling JIT-compiled functions on host-memory arrays without an explicit copy or using another third-party library as an intermediary.

// https://gitlab.com/tnl-project/pytnl/-/merge_requests/74
// https://gitlab.com/tnl-project/pytnl/-/merge_requests/73
Given these developments, only the Python Buffer protocol implementation was ultimately merged into the PyTNL repository. The CUDA Array interface implementation, while functional, was not included in the final codebase as it offered no remaining advantage over the pre-existing DLPack support. #mcite(<c_pytnl-buffer-mr>, <c_pytnl-cai-mr>)

=== Technical remarks

From a technical standpoint, the implementation of each protocol is relatively straightforward. The protocols primarily require populating their respective structures (`Py_buffer` for the Buffer protocol, the `__cuda_array_interface__` dictionary for CAI) with metadata describing the memory layout, data type, shape, and strides of the underlying array. This information is readily available from the internal representation of PyTNL's container types.

A notable detail concerns the Buffer protocol specifically. Unlike DLPack and the CUDA Array interface, which expose Python-level methods (`__dlpack__`, `__dlpack_device__`, `__cuda_array_interface__`), the Buffer protocol is implemented entirely at the C API level through type slots (`bf_getbuffer` and `bf_releasebuffer`). The protocol has no corresponding Python-side special methods in Python versions prior to 3.12. Since PyTNL's bindings are built using nanobind, the buffer support is registered through the appropriate slot mechanism rather than as a Python method.


== Unlocked possibilities and usage

With the protocol implementations in place, PyTNL's array containers become consumable by any library that understands the corresponding interchange mechanism. This section describes the concrete capabilities that these protocols enable, organized around four objectives:

+ *Zero-copy interoperability.* Although PyTNL aims to be a self-contained library, allowing the no-copy views in other libraries gives users the freedom to use the best tool for the job. And thanks to sharing the buffer, the modifications are made immediately accessible even in the originating PyTNL array.
+ *Direct execution of JIT-compiled functions on PyTNL containers.* Through the Buffer protocol (CPU) and DLPack (CUDA), Numba-compiled functions and kernels can operate directly on PyTNL arrays without requiring an explicit data copy or conversion. This includes scalar JIT functions, vectorized operations, and multi-dimensional CUDA kernels.
+ *Applicability to non-array data structures.* The protocols are defined for dense, contiguous memory regions and therefore map naturally onto `NDArray`. But positive impact can be seen even in some more complex data structures. For example, sparse formats such as CSR matrices store their data in multiple separate arrays (values, column indices, row pointers), each of which can be individually exported. This section explores what operations this partial exposure enables and where its limitations lie.
+ *Performance evaluation.* The element-wise operations executed through the protocol-based direct access are benchmarked and compared against the results from @function_calling_from_cpp_benchmark, where Python functions were passed across the language boundary into the #cpp runtime.

=== Zero-copy interoperability

The zero-copy interoperability is demonstrated on a very simple use case. After PyTNL array initialization, user needs to be able to create a view of the data in another library, modify it in place and see the changes reflected in the original PyTNL array. In fact, the same should apply the other way around and changes in the original data need to be visible in the view as well.

#code1(
  [Bidirectional zero-copy sharing via all three interchange protocols. All assertions pass.],
  <zero_copy_interop_example>,
  ```python
  N = 5

  # Buffer protocol — host array shared with NumPy
  host_arr = Array[float, devices.Host](N, 1.0)
  np_view = np.asarray(host_arr)   # via Buffer protocol

  host_arr[0] = 42.0
  assert np_view[0] == 42.0        # modification visible through NumPy view

  np_view[1] = 99.0
  assert host_arr[1] == 99.0       # modification visible through PyTNL array

  # CUDA Array interface — CUDA array shared with CuPy
  cuda_arr = Array[float, devices.Cuda](N, 2.0)
  cp_view = cp.asarray(cuda_arr)   # via __cuda_array_interface__

  cuda_arr[0] = 42.0
  assert float(cp_view[0]) == 42.0

  cp_view[1] = 99.0
  assert cuda_arr[1] == 99.0

  # DLPack — CUDA array shared with CuPy
  cuda_arr2 = Array[float, devices.Cuda](N, 3.0)
  cp_view2 = cp.from_dlpack(cuda_arr2)    # via DLPack

  cuda_arr2[0] = 42.0
  assert float(cp_view2[0]) == 42.0

  cp_view2[1] = 99.0
  assert cuda_arr2[1] == 99.0
  ```,
)

This example is, of course, very simple, but as the changes do not propagate by some kind of synchronization mechanism but rather simply through shared memory, the same principle applies to any kind of modification as long as the operation doesn't require a copy or reallocation due to shape changes.

This allows users to leverage the strengths of different libraries on the same data with little to no performance penalty.

=== JIT-compiled operations on arrays

// TODO: Rewrite when the first benchmark results are actually written
As the benchmarks in @function_calling_from_cpp_benchmark suggests, a big performance bottleneck in executing element-wise operations are the constant crossings of the language boundary, the type conversions, boxing and unboxing of Python objects and rest of the overhead. Now just the inversion of approach and calling the user functions from Python loops instead of #cpp is not a sufficient solution. Function like the one shown in @slow_python_map_function still crosses the boundary two times for each element, once when the element is read and once when it is written back. Each time, the `double` value is converted to a Python float object and back. Furthermore, the Python for loop execution itself is simply slower then the equivalent C++ loop.

#code1(
  [Element wise mapping using a plain Python loop. Generally low performance both for the Python loop but mainly for the many element accesses that require crossing the language boundary.],
  <slow_python_map_function>,
  ```python
  def python_map(data, func) -> None:
      """Element-wise mapping using a plain Python loop."""
      for i in range(data.size):
          data[i] = func(data[i])
  ```,
)

The data transfer protocols however finally give us the ability to eliminate these bottlenecks entirely. Instead of accessing the data element by element through the bindings, the protocols allow direct access to the underlying memory buffer. When combined with Numba's JIT compilation, this means that user-defined Python functions can be compiled to native machine code and executed directly on the raw data --- without ever crossing the language boundary during the computation itself. The boundary is crossed only once, when the protocol exports the buffer reference, and the compiled function then operates on it at native speed.

An important consequence of this approach is that the user-defined functions must be written to accept the _entire buffer_ rather than a single element. Since the protocol exports a raw memory view, the JIT-compiled function receives the whole array and is responsible for iterating over it internally. This is the opposite of the element-wise callback pattern familiar from TNL's `forAll` or the `python_map` function shown above, where the user supplies a per-element function and the library drives the loop.

Another consequence is that what Numba sees is not a PyTNL object with its methods and attributes, but a bare typed buffer. When a PyTNL host array is passed into a `@jit`-compiled function, Numba resolves it through the Buffer protocol and internally represents it as a simple typed memory view --- for instance `buffer(float64, 1d, C)`. No PyTNL methods, properties, or Python-level attributes are available inside the compiled function. The user can index into the buffer, query its length, and perform arithmetic, but cannot call, say, `data.getElement()` or any other PyTNL-specific API. This is a fundamental constraint: the protocol gives direct memory access, but strips away the source object's interface entirely.

With that in mind, three Numba compilation modes are shown below, each operating directly on PyTNL arrays through the implemented protocols.

==== Numba `@jit` --- CPU JIT-compiled loops

The `@jit(nopython=True)` decorator (equivalently `@njit`) compiles a Python function into optimized machine code ahead of its first execution. Within the compiled function, all loop iterations and array accesses are performed at native speed with no Python interpreter involvement. This mode consumes PyTNL host arrays through the Buffer protocol.

#code1(
  [A Numba `@jit`-compiled function that mutates a PyTNL host array in place. The function receives the entire buffer and iterates over it internally.],
  <numba_jit_example>,
  ```python
  @jit(nopython=True)
  def fill_with_index_njit(data):
      """Fill a 1D array with values matching their indices."""
      for i in range(len(data)):
          data[i] = i

  # Usage with PyTNL array
  host_arr = Array[float, devices.Host](N, 0.0)
  fill_with_index_njit(host_arr)  # runs at native speed via Buffer protocol
  ```,
)

Note that the function accepts the whole array and contains its own loop. The user has full control over the iteration, indexing, and any conditional logic. This is particularly powerful for operations that do not map cleanly onto existing library primitives --- custom reductions, conditional updates, or any loop-heavy algorithm that would otherwise require dropping into #cpp.

The disadvantage is that the user not only can, but must, write the loop themselves. That loses some of the convenience of simple element-wise operations and the original `parallelFor` TNL function.

Still, the key insight is that this allows users to write standard Python code and as will be seen later in a benchmark, this happens without the usual performance costs associated with Python.

==== Numba `@vectorize` --- element-wise shortcut <numba_vectorize_usage>

The `@vectorize` decorator is a notable exception to the whole-buffer pattern. It takes a scalar function --- one that operates on individual elements --- and lifts it into a NumPy-style universal function (ufunc) that Numba applies element-wise over the entire array. The user defines only the per-element logic; Numba handles the iteration and broadcasting internally. This mode also consumes host arrays through the Buffer protocol.

#code1(
  [A Numba `@vectorize`-compiled ufunc applied to a PyTNL host array. Unlike `@jit`, the user defines only scalar logic and Numba drives the loop.],
  <numba_vectorize_example>,
  ```python
  @vectorize(["float64(float64, float64)"], nopython=True)
  def vectorized_scale(x, scale):
      """Element-wise scale as a Numba vectorized ufunc."""
      return x * scale

  host_arr = Array[float, devices.Host](N, 1.0)
  result = vectorized_scale(host_arr, 2.0)  # returns a NEW NumPy array
  ```,
)

While concise, `@vectorize` has an important caveat: by default it allocates and returns a _new NumPy array_ rather than modifying the input in place. The result is not written back into the original PyTNL buffer. The NumPy ufunc convention does allow an `out=` parameter to redirect the output into an existing array, but this only works when the target is itself a NumPy array. With a PyTNL array passed directly as `out=`, the call fails. A workaround is to first create a NumPy view of the PyTNL array via `np.asarray()` (which itself uses the Buffer protocol and is zero-copy) and pass _that_ as the output target:

#code1(
  [Workaround for in-place `@vectorize` output: creating a zero-copy NumPy view and passing it as the `out` argument redirects the result back into PyTNL's buffer.],
  <numba_vectorize_inplace_workaround>,
  ```python
  host_arr = Array[float, devices.Host](N, 1.0)
  np_view = np.asarray(host_arr)                   # zero-copy NumPy view
  vectorized_scale(host_arr, 2.0, out=np_view)     # writes into PyTNL's memory
  # host_arr now contains the scaled values
  ```,
)

This is admittedly not the most elegant pattern, but it does preserve the zero-copy property and avoids any data duplication. For use cases where in-place mutation and full loop control matter, `@jit` remains the more natural choice.

==== Numba `@cuda.jit` --- GPU kernel execution

For arrays residing in device memory, the `@cuda.jit` decorator compiles a Python function into a CUDA kernel that executes directly on the GPU. As with `@jit`, the function receives the entire array rather than individual elements. However, writing a CUDA kernel requires somewhat more understanding of the GPU execution model than a simple CPU loop.

The kernel is launched over a _grid_ of threads organized into _blocks_. Each thread computes its own position in the grid using `cuda.grid()` and operates on the corresponding array element(s). Because the total number of threads is typically rounded up to fill complete blocks, the grid may be larger than the array. The bounds check (`if i < nx ...`) ensures that threads falling outside the valid range do not access out-of-bounds memory --- without this guard, the kernel would produce undefined behaviour.

#code1(
  [A 3D CUDA kernel written with Numba's `@cuda.jit`, launched directly on a PyTNL CUDA `NDArray`. The `blocks` and `threads` parameters define the execution grid; the `if` guard prevents out-of-bounds access.],
  <numba_cuda_jit_3d_example>,
  ```python
  @cuda.jit
  def numba_scale_kernel_3d(data, scale, nx, ny, nz):
      """Scale a 3D NDArray element-wise on the GPU."""
      i, j, k = cuda.grid(3)
      if i < nx and j < ny and k < nz:
          data[i, j, k] = data[i, j, k] * scale

  cuda_arr = NDArray[float, devices.Cuda]((nx, ny, nz), 1.0)
  threads = (8, 8, 8)
  blocks = ((nx + 7) // 8, (ny + 7) // 8, (nz + 7) // 8)
  numba_scale_kernel_3d[blocks, threads](cuda_arr, 2.0, nx, ny, nz)
  ```,
)

The ability to write CUDA kernels in Python and launch them directly on PyTNL device arrays is perhaps the most significant capability unlocked by the protocol implementations. Users can implement custom GPU algorithms --- stencil operations, reductions, or application-specific kernels --- without writing any #cpp or CUDA C code, while still operating on the same memory that PyTNL manages.

The following example demonstrates a non-trivial access pattern where each thread reads from three neighboring positions, as is typical in finite difference stencil computations:

#code1(
  [A 1D stencil kernel demonstrating neighbor access patterns on a PyTNL CUDA array. The bounds check `0 < i < N - 1` excludes boundary elements that lack a full neighborhood.],
  <numba_stencil_example>,
  ```python
  @cuda.jit
  def numba_stencil_kernel(input_data, output_data, N):
      """3-point stencil operation (like finite differences)."""
      i = cuda.grid(1)
      if 0 < i < N - 1:
          output_data[i] = (input_data[i-1] + input_data[i] + input_data[i+1]) / 3.0

  input_arr = Array[float, devices.Cuda](N, 0.0)
  output_arr = Array[float, devices.Cuda](N, 0.0)
  # ... initialize input_arr ...
  threads = 256
  blocks = (N + threads - 1) // threads
  numba_stencil_kernel[blocks, threads](input_arr, output_arr, N)
  ```,
)

This goes beyond simple element-wise operations and demonstrates that the exported buffer is fully addressable from within the Numba-compiled kernel, including relative indexing over neighboring elements. The compiled kernel has the same access to the raw memory as a hand-written CUDA C kernel would.

=== Sparse matrix access

So far, the examples and focus have been only on dense, multidimensional, arrays. That however is not the only data structure TNL supports. This section briefly demonstrates how the array transfer protocols can be useful even for the more complex data structures such as sparse matrices.

==== CSR Format

// https://docs.scipy.org/doc/scipy/reference/generated/scipy.sparse.csr_matrix.html
The Compressed Sparse Row (CSR) format is one of the most common sparse matrix representations. Instead of of storing all the elements in a two-dimensional array, it uses three separate one-dimensional arrays to represent only the non-zero values and their positions: #cite(<c_scipy-csr-matrix>)

- `VALUES` array contains all the non-zero values sorted from top to bottom and left to right. Matrix of $N$ non-zero elements will have `VALUES` of length $N$.
- `COLUMN_INDICES` array contains the column index record for each value in `VALUES`. It has the same length as `VALUES`.
- `ROW_POINTERS` array specifies the distribution of values across rows. Each entry corresponds to one row and contains the index in `VALUES`, and `COLUMN_INDICES`, where the row starts. If matrix consists of $M$ rows, `ROW_POINTERS` will have length $M + 1$, with the last entry pointing to the end of the `VALUES` array.

// https://docs.nvidia.com/nvpl/latest/sparse/storage_format/sparse_matrix.html#compressed-sparse-row-csr
// https://docs.nvidia.com/nvpl/latest/sparse/storage_format/sparse_matrix.html#compressed-sparse-row-csr
#figure(
  image("assets/csr_example.png", width: 85%),
  caption: [Illustrative example of the CSR format for a sparse matrix. #cite(<c_nvpl-sparse>)],
)

==== Benefits of array backed data structures

As the CSR matrix still uses dense arrays under the hood, it can still benefit from the implemented protocols. Each of the three internal arrays can be exported individually, allowing users to perform custom operations on them using the same zero-copy interoperability and JIT compilation capabilities described above. For instance, a user could write a Numba `@cuda.jit` kernel that operates directly on the `VALUES` array to apply a custom element-wise transformation, as demonstrated below.

#code1(
  [Scaling the `VALUES` array of a CSR matrix in-place via a `@cuda.jit` kernel. Only the dense backing array is exported; the structural arrays (`COLUMN_INDICES`, `ROW_POINTERS`) remain untouched.],
  <csr_scale_example>,
  ```python
  cuda_values  = Array[float, devices.Cuda](4, 0.0)
  cuda_col_idx = Array[int,   devices.Cuda](4, 0)
  cuda_row_ptr = Array[int,   devices.Cuda](5, 0)
  # ... fill with [10, 20, 30, 40], [0, 1, 2, 1], [0, 1, 3, 3, 4] ...

  # Scale all non-zero values in-place via a CUDA kernel on VALUES directly
  @cuda.jit
  def scale_values(values, factor, n):
      i = cuda.grid(1)
      if i < n:
          values[i] *= factor

  n = 4
  threads = 32
  blocks = (n + threads - 1) // threads
  scale_values[blocks, threads](cuda_values, 2.0, n)

  # Zero-copy CuPy view confirms the modification
  cp_values = cp.asarray(cuda_values)
  assert cp_values.tolist() == [20.0, 40.0, 60.0, 80.0]  # all values doubled
  ```,
)

// https://docs.scipy.org/doc/scipy/reference/generated/scipy.sparse.csr_matrix.html
// https://docs.cupy.dev/en/stable/reference/generated/cupyx.scipy.sparse.csr_matrix.html
This approach does come with a usability cost: the user must understand the internal data structure and is limited to operations that touch only one backing array at a time. However, it requires almost no additional effort on the library side — public exposure of the internal arrays is sufficient, and libraries like SciPy and CuPy already provide this. In general, any data structure backed by dense arrays can benefit from the protocols to some extent, even if it is not strictly array-like in its public API. #mcite(<c_scipy-csr-matrix>, <c_cupy-csr-matrix>)

=== Performance evaluation <protocol_performance_evaluation>

To sum up the demonstration, benchmark evaluates the performance of the protocol-based direct access approach for executing element-wise operations on PyTNL arrays. The goal is to compare the performance of executing a simple JIT compiled element-wise scaling operation directly on data exposed through the protocols against the results from @function_calling_from_cpp_benchmark, where the same operation was implemented by passing Python functions into the #cpp runtime.

The benchmark measures the same operation --- scaling every element of a $2^21$-element array by a constant factor --- across all methods demonstrated in the preceding sections, as well as baseline approaches that include plain Python loops and NumPy's built-in ufunc. Each method was timed over multiple iterations and the average per-iteration time is reported. All the JIT compiled functions and kernels were warmed-up so the compilation overhead is excluded. The results are summarized in @benchmark_user_functions_protocol_table.

#figure(
  table(
    columns: (1fr, auto, auto, auto, auto),
    align: (left, left, center, right, right),
    inset: (x: 8pt, y: 10pt),
    table.header([*Method*], [*Data Structure*], [*Device*], [*Avg \ (ms/iter)*], [*Speedup*]),
    [cuda.jit], [PyTNL NDArray], [GPU], [0,093], [9,0645x],
    [cuda.jit], [CuPy array], [GPU], [0,094], [8,9681x],
    [Numba jit], [PyTNL NDArray], [CPU], [0,795], [1,0604x],
    [Numba jit], [NumPy array], [CPU], [0,81], [1,0407x],
    [NumPy ufunc], [NumPy array], [CPU], [0,843], [1,0000x],
    [Numba vectorize], [NumPy array], [CPU], [1,195], [0,7054x],
    [Numba vectorize], [PyTNL NDArray], [CPU], [1,31], [0,6435x],
    [python loop], [Python list], [CPU], [70,179], [0,0120x],
    [python loop], [NumPy array], [CPU], [589,413], [0,0014x],
    [PyTNL forAll], [PyTNL NDArray], [CPU], [744,411], [0,0011x],
    table.hline(stroke: 1.5pt),
  ),
  caption: [
    Element-wise scale benchmark across methods and data structures, $N = 2^(21) = 2 thin 097 thin 152$,
    sorted fastest to slowest. Speedup is relative to NumPy scale on a NumPy array.
    The benchmark ran on a PC with Ryzen 3600 CPU and NVIDIA RTX 3070 GPU in WSL2 environment.
  ],
) <benchmark_user_functions_protocol_table>

The most important observation is that PyTNL arrays accessed through the protocols perform on par with their native counterparts. Numba `@jit` on a PyTNL host array (0.795 ms) is virtually identical to the same function on a NumPy array (0.810 ms), and both match the NumPy ufunc baseline (0.843 ms). Similarly, `@cuda.jit` on a PyTNL CUDA `NDArray` (0.093 ms) is indistinguishable from the same kernel on a CuPy array (0.094 ms). This confirms that the protocol-based export introduces only negligible overhead --- once the buffer reference is handed off, the JIT-compiled code operates on raw memory at the same speed regardless of the originating library.

On the GPU side, the `cuda.jit` results are roughly 9× faster than the CPU baseline, which is expected given the massively parallel nature of the operation and the hardware used. This is further supported by the fact that increasing $N$ does not significantly change the per-iteration time on the GPU, while it does rise linearly on the CPU, confirming the parallel nature of the execution.

The `@vectorize` results (1.2--1.3 ms) are somewhat slower than the `@jit` approach, which is consistent with the additional overhead of the ufunc dispatch machinery. Note that in the benchmark, the workaround mentioned in @numba_vectorize_usage was used to achieve in-place mutation. So the slowdown is not caused by extra allocation. Still, the performance difference is very slight and seems to be a reasonable tradeoff for the convenience of writing scalar logic without explicit loops.

// TODO: Check the sentence makes sense after the first benchmark chapter is actually written
The bottom of the table reveals the critical comparison with @function_calling_from_cpp_benchmark. The `PyTNL forAll` row, where a Python callback is passed into the #cpp runtime and invoked for each element, clocks in at 744 ms --- over 883× slower than the NumPy baseline. This is the cost of crossing the language boundary on every single element access, as discussed earlier in this chapter. By contrast, the protocol-based approach with Numba `@jit` on the same PyTNL array achieves 0.795 ms, showcasing the same performance characteristics as native executions. The language boundary is crossed exactly once, when the buffer view is exported, and the compiled function then runs entirely in native code.

Even the plain Python loop on a Python list (70 ms), which avoids the binding overhead entirely but suffers from interpreter slowness, is still 88× slower than the JIT-compiled protocol path. The Python loop on a NumPy array (589 ms) is even worse, as each element access through `__getitem__` and `__setitem__` involves boxing and unboxing Python objects --- the same fundamental overhead that slows the `forAll` approach.

These results validate the central thesis of this chapter: exposing PyTNL's memory through standard interchange protocols and letting the user drive computation from the Python side with JIT compilation is not merely a viable alternative to passing callbacks into #cpp. It is dramatically faster, while simultaneously offering a relatively straightforward API that users of Python scientific libraries are already familiar with.
