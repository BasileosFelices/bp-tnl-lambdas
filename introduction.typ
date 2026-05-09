#import "ctufit-thesis.typ": *

High-performance numerical software is often implemented in #cpp, but much of scientific work is done in higher-level languages such as Python or Julia. This creates a usability gap: users want the flexibility of interactive scripting and rapid experimentation without giving up native performance.

This thesis focuses on the Template Numerical Library (TNL) and on expanding its Python interface, PyTNL. If TNL is to be useful beyond developers already comfortable with modern #cpp, it needs interfaces that fit the way many researchers and practitioners actually work.

The goal of this work is to find efficient ways to execute user-defined Python operations on core TNL data structures without losing the performance of native TNL code.

Its practical relevance is illustrated on TNL-SPH as a demonstration case for a more accessible Python driven workflow. The thesis also briefly considers Julia as a possible direction for future interface development and identifies promising tools for that purpose.

The thesis is structured as follows:

- *Chapter 1* introduces the main components on which this work builds: TNL, PyTNL, the CUDA programming model, the nanobind binding library, and comparable numerical libraries used as reference points.
- *Chapter 2* introduces the problem of higher-order functions in TNL, the constraints nanobind imposes when Python callables are passed as callbacks, and the attempt to use Numba JIT compilation and NVRTC-based GPU kernel compilation to overcome the performance gap.
- *Chapter 3* introduces the data-interchange protocols used in this work and explains how they allow JIT compiled functions to operate directly on TNL memory without any performance penalties.
- *Chapter 4* introduces the TNL-SPH demonstration case and shows how code generation and runtime compilation can simplify the current user workflow.
- *Chapter 5* introduces the potential benefits of a Julia interface to TNL and outlines tools that could be used to build the necessary bindings.
