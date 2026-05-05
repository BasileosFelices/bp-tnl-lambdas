#let cpp = box[C#h(-0.05em)++\u{2060}]

This thesis investigated the design of efficient interfaces for the Template Numerical Library (TNL) in high-level environments, with the implemented work focused primarily on Python and with Julia considered as a prospective direction. 

The central challenge was to enable user-defined functions and CUDA kernels to interact with TNL core data structures without incurring prohibitive overhead from Python execution and language-boundary crossings.

=== Key findings

The evaluation showed that a direct translation of #cpp higher-order functions, in which Python callables are passed as per-element callbacks, is technically feasible for host-side execution but unsuitable for performance-critical workloads. 

The benchmark results indicated that this approach can be more than 800 times slower than native execution, largely due to repeated boxing and unboxing of Python objects.

The most effective implemented solution was an inversion of control based on zero-copy data-interchange protocols. By implementing the Python Buffer Protocol and leveraging existing DLPack support, TNL arrays were made directly accessible to Numba JIT-compiled functions. 

In the evaluated scenarios, this substantially reduced boundary overhead and enabled Python-driven code to achieve performance comparable to native NumPy and CuPy workflows.

=== Practical Application: TNL-SPH

The practical relevance of these findings was illustrated through a proof-of-concept extension of PyTNL toward the TNL-SPH module. By developing a Just-in-Time plugin architecture, the thesis showed that a manual #cpp/CMake workflow can be partially streamlined through a Python-driven interface. The resulting system was able to generate, compile, and cache simulation variants on demand, providing evidence that this approach is feasible for selected SPH use cases and may improve accessibility for users without deep knowledge of #cpp templates or build systems.

=== Future Work

While the implemented Python interface demonstrates the practicality of the proposed approach, several paths for expansion remain:

- *Simulation interface expansion*: Extending the JIT-compilation approach to cover a broader range of simulation scenarios and user-defined components.
- *Data access expansion*: Exposing non-owning array views across the ABI boundary to enable direct manipulation of SPH particle data through the established zero-copy mechanisms.
- *Julia implementation*: The technical analysis identified CxxWrap.jl as a promising basis for a future native Julia interface (jTNL), but this direction remains to be validated by implementation and evaluation.

In summary, the presented results indicate that high-performance libraries such as TNL can be integrated effectively into high-level ecosystems when interoperability mechanisms are chosen with respect to the performance model of modern JIT compilers. A central design lesson of this work is that zero-copy memory sharing is a more suitable foundation for such integration than a direct imitation of native #cpp callback-based syntax.