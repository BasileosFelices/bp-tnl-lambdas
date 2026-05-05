#let cpp = box[C#h(-0.05em)++\u{2060}]

This thesis investigated the development of efficient interfaces for the Template Numerical Library (TNL) in high-level environments, specifically Python and Julia. The primary challenge was allowing user-defined functions and CUDA kernels to run in the TNL's core without the usual performance penalties associated with Python and language boundary crossings.

=== Key findings 

The research showed that a literal translation of #cpp higher-order functions, passing Python callables as per-element callbacks, is possible for host based code but architecturally unsuitable for performance-critical tasks. Benchmarks revealed that this approach is over 800 times slower than native execution due to constant boxing and unboxing of objects.

The most effective solution implemented was the "inversion of control" via zero-copy data-interchange protocols. By implementing the Python Buffer Protocol and leveraging existing DLPack support, TNL arrays were made directly accessible to Numba JIT-compiled functions. This approach effectively eliminated the boundary cost, allowing Python-driven code to perform on par with native NumPy and CuPy operations.

=== Practical Application: TNL-SPH

The practical utility of these findings was demonstrated through a proof-of-concept extension of PyTNL toward the TNL-SPH module. By developing a Just-in-Time plugin architecture, the thesis showed that a complex, manual C++/CMake workflow can be substantially streamlined through a Python-driven interface. The resulting system successfully generated, compiled, and cached simulation variants on demand, demonstrating the viability of this approach for making advanced SPH simulations more accessible to users without deep knowledge of C++ templates or build systems.

=== Future Work

To achieve production-level robustness, several paths for expansion remain:

- *Stronger simulation interface*: Extending the JIT-compilation approach to cover more use cases and simulation scenarios.
- *Data Access Expansion*: Future iterations should focus on exposing non-owning array views across the ABI boundary to allow manipulation of particle data in SPH simulations through the implemented zero-copy protocols.
- *jTNL Implementation*: The technical analysis identified `CxxWrap.jl` as the most promising foundation for a future native Julia interface (jTNL). For time constraints, the thesis did not implement a jTNL prototype, but future work could explore this direction to further expand TNL's accessibility and performance in the Julia ecosystem.

In summary, this work confirms that high-performance libraries like TNL can be successfully integrated into high-level ecosystems. The key to success lies in choosing interoperability mechanisms -- like zero-copy memory sharing -- that respect the performance models of modern JIT compilers rather than simply mimicking native #cpp syntax.