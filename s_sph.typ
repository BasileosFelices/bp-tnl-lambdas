#import "ctufit-thesis.typ": *
#let cpp = box[C#h(-0.1em)++\u{2060}]

== TNL-SPH

// https://papers.ssrn.com/sol3/papers.cfm?abstract_id=5671636

// TODO: Consider adding citations for the original SPH papers (Lucy 1977, Gingold & Monaghan 1977)
// R. A. Gingold and J. J. Monaghan. Smoothed particle hydrodynamics: theory and application to non-spherical stars. Monthly Notices of the Royal Astronomical Society, 181:375–389, 1977.
Smoothed Particle Hydrodynamics (SPH) is a fully Lagrangian mesh-free method originally developed for astrophysical simulations, which has since been widely adopted in engineering, geophysics, and computer graphics for its ability to handle complex geometries, discontinuities, and free surfaces.

TNL-SPH @halada2025tnlsph is an open-source SPH implementation developed as a submodule of the Template Numerical Library. TNL-SPH focuses on fluid flow modeling, and hydrodynamic problems in general, while providing a relatively high level, user-friendly interface, just like the rest of TNL. The library is designed with easy access to and extension of the main time loop in mind, allowing users to insert custom functions between any two operations in the loop.

The existing examples already ship with Python scripts that prepare the simulation configuration, run the simulation, and post-process the results. That makes TNL-SPH an ideal demonstration case for this work. If the whole user flow could be moved to Python --- with no manual compilation step and no subprocess launching --- that would be a significant improvement in the user experience and accessibility of the library.

=== PyTNL goals - workflow

==== Current workflow <sph_current_workflow>

The native TNL-SPH workflow, as described in the paper @halada2025tnlsph and its accompanying examples, involves three configuration files per simulation case. A compile-time configuration header `config.h` selects the device, particle representation, SPH model, and all of its associated template parameters --- kernel function, diffusive term, viscous term, equation of state, boundary condition type, time stepping strategy, and integration scheme. A runtime configuration file `config.ini` specifies physical and numerical parameters such as density, speed of sound, viscosity, CFL number, and paths to initial particle distributions. Finally, `case.h` contains the #cpp `main()` function that creates the solver instance and defines the simulation time loop.

The time loop in `case.h` is structured as a sequence of individual phase calls, each corresponding to a distinct step of the SPH algorithm. This is deliberate: it allows users to insert custom logic between any two phases of the simulation.

#code1(
  [The native #cpp time loop from a TNL-SPH example (adapted from the paper's Appendix~A @halada2025tnlsph). Each simulation phase is a separate method call, and the loop is explicitly designed for user extensibility.],
  <sph_native_case_h>,
  ```cpp
  #include "template/config.h"

  int main( int argc, char* argv[] )
  {
      Simulation sph;
      sph.init( argc, argv );
      sph.writeProlog();

      while( sph.timeStepping.runTheSimulation() )
      {
          sph.performNeighborSearch();
          sph.interact();
          sph.computeTimeStep();
          sph.integrateVerletStep( SPHDefs::BCType::integrateInTime() );
          sph.makeSnapshot();
          sph.measure();
          sph.updateTime();
      }

      sph.writeEpilog();
  }
  ```,
)

While the loop itself is simple and straightforward, setting up the input data and configuration can still be a daunting task for new users. The compile-time configuration requires familiarity with C++ templates and the specific types defined in the TNL-SPH codebase. The runtime configuration involves editing an INI file with the correct parameter names and values as well as preparing the initial particle distribution in the Visualization Toolkit (VTK) format.

To help with this, the library ships with several Python scripts. The `init.py` generates the runtime configuration and the VTK files. It also performs text substitution in the `config_template.h` to generate the final `config.h`, filling in the three substituted parameters --- `DiffusiveTerm`, `ViscousTerm`, and `BCType` --- while the remaining template parameters (kernel function, EOS, time stepping, and integration scheme) are hardcoded in the template.

After that however, the user must still manually compile the C++ code via `cmake --build build`, since the template parameters are baked into the generated header. The `run.py` script then serves a dual role: it conditionally invokes `init.py` as a subprocess --- either when the `--init` flag is passed explicitly, or automatically when the `sources/` directory does not yet exist --- and subsequently launches the compiled binary as a subprocess with the generated configuration. Finally, `postpro.py` reads the plain-text sensor measurement files (`sensorsPressure.dat`, `sensorsWaterLevel.dat`) and generates matplotlib plots from them. It also calls `writeParaviewSeriesFile.generate_series()` to produce a `.pvd` index file over the VTK snapshots, which allows ParaView to load the full simulation sequence.

==== Simplified workflow goals

The PyTNL expansion aims to collapse this multi-step process into a single Python script. Instead of separate initialisation, compilation, and execution phases --- each requiring different tools and knowledge --- the user should be able to specify the simulation configuration through Python methods and functions and drive the simulation time loop directly from Python.

The key goals of PyTNL-SPH are:

+ No manual #cpp compilation --- the simulation is already compiled along with the library, or as the @sph_code_generation describes, the JIT plugin system compiles the variant on the spot and caches it by default.
+ No subprocess launching --- the simulation runs directly within the Python process.
+ No need to edit #cpp configuration headers --- all template parameters are selected through Python arguments.
+ User-defined functions can be written in Python --- including the possibility of JIT-compiled Numba functions operating on the solver's arrays through the data interchange protocols described in the preceding chapter --- rather than requiring #cpp code that must be compiled with the project.

// TODO: Once the API is finalised, add a side-by-side comparison (table or two columns) showing the traditional three-step workflow vs. the single-script PyTNL approach.

=== Template instantiation <sph_template_instantiation>

The compile-time template configuration described in @sph_current_workflow creates a challenge for Python bindings. In native #cpp, the compiler instantiates templates on demand --- the user edits `config.h`, and only the requested combination of types is compiled. Nanobind, however, requires every template instantiation it wraps to be explicitly enumerated and compiled in advance. There is no mechanism to defer instantiation to runtime; the set of supported types is fixed when the extension module is built.

To illustrate the scale of the problem, @sph_config_h shows how a single variant is assembled in `config.h`, and @sph_template_axes lists all available configuration axes:

#code1(
  [Compile-time configuration of a TNL-SPH simulation variant in `config.h` (adapted from the paper's Appendix~A @halada2025tnlsph). Each `using` declaration selects a specific implementation for one template axis; the final `Model` and `Simulation` types compose all choices into a single #cpp type.],
  <sph_config_h>,
  ```cpp
  class SPHParams {
      using KernelFunction =
          TNL::SPH::WendlandKernel<SPHConfig<Device>>;
      using DiffusiveTerm =
          TNL::SPH::MolteniDiffusiveTerm<SPHConfig<Device>>;
      using ViscousTerm =
          TNL::SPH::ArtificialViscosity<SPHConfig<Device>>;
      using EOS =
          TNL::SPH::TaitWeaklyCompressibleEOS<SPHConfig<Device>>;
      using BCType = TNL::SPH::DBC;
      using TimeStepping =
          TNL::SPH::ConstantTimeStep<SPHConfig<Device>>;
      using IntegrationScheme =
          TNL::SPH::VerletScheme<SPHConfig<Device>>;
  };
  using Model =
      TNL::SPH::WCSPH_DBC<ParticlesSys, SPHParams<Device>>;
  using Simulation =
      TNL::SPH::SPHMultiset_CFD<Model>;
  ```,
)

#figure(
  table(
    columns: (auto, auto, auto),
    align: (left, left, left),
    inset: (x: 8pt, y: 10pt),
    table.header([*Parameter*], [*Options*], [*Count*]),
    [Boundary condition], [DBC, MDBC], [2],
    [Diffusive term], [None, Molteni, Fourtakas], [3],
    [Viscous term], [Artificial, Physical, Combined], [3],
    [Kernel function], [Wendland], [1],
    [Time stepping], [Constant, Variable], [2],
    [Device], [Host (CPU), CUDA (GPU)], [2],
    [Precision], [float, double], [2],
    [Dimension], [2D, 3D], [2],
  ),
  caption: [Compile-time configuration axes of the SPH solver and their respective options.],
) <sph_template_axes>

The total number of distinct combinations is:
$ 2 times 3 times 3 times 1 times 2 times 2 times 2 times 2 = 288 $

Pre-compiling all 288 variants into a single extension module is impractical. CUDA compilation through `nvcc` is slow --- each variant requires processing the entire heavily-templated SPH header hierarchy, and the total build time would be very long. The resulting binary would also be unnecessarily bloated, and any change to the set of options (adding a new kernel function, for example) would multiply the variant count further.

That leaves two choices:

+ Analyze the domain and identify a smaller subset of "common" variants to compile in advance. Users needing other configurations would either have to modify the source code or simply revert to the traditional #cpp workflow.
+ Generate and compile the requested variant on demand at runtime. Potentially caching the results to avoid recompilations.

Given this work's goal of improving accessibility and user experience, the second option was chosen. The following sections describe the runtime code generation and compilation system implemented for TNL-SPH.

=== Code generation <sph_code_generation>

// TODO: Check there are experiments describing this...:d
Experiments described in @nvrtc_introduction demonstrate that runtime compilers like NVRTC fail to compile the heavily-templated TNL code base, whose design relies on device-independent user code that runs on both CPU and GPU. The code generation therefore relies on the standard toolchain.

CMake is used to configure and drive the compilation, and `nvcc` is used to compile the CUDA variants. This requires the user to have the full toolchain installed. That is, however, already expected of users who build the original TNL-SPH from source, so it does not represent an additional barrier. No new dependencies are introduced.

==== Variant specification

The eight compile-time axes are modelled in Python as `Enum` classes whose `.value` strings correspond to the exact #cpp type names used in substitution. A frozen dataclass `VariantSpec` bundles all axes into a single hashable, immutable descriptor. Its `variant_id()` method produces a filesystem-safe string (e.g., `wcsph_dbc_2d_cuda_float_dbc_molteni_artificial`) that serves as both the cache key and the generated CMake project name.

==== Source generation

The code generator uses simple `{{TOKEN}}` placeholder substitution --- no external templating engine such as Jinja2 is required, keeping the dependency footprint minimal. After substitution, a regex check verifies that no unresolved `{{UPPER_CASE}}` placeholders remain, catching typos and missing parameters early.

For each variant, two files are produced:

+ *`plugin.cpp`* --- a self-contained #cpp translation unit (~210 lines) that defines the fully-resolved type aliases for the particle system configuration, SPH parameters, and the simulation model --- essentially the logic previously in the compile-time `config.h`. It also exports three `extern "C"` entry points: `sph_create()`, `sph_destroy()`, and `sph_variant_id()`. The `extern "C"` linkage prevents #cpp name mangling and establishes a stable C ABI across separately compiled modules. After loading the compiled plugin, the host finds these functions via `dlsym` and uses them to create and manage the simulation instance.

+ *`CMakeLists.txt`* --- a standalone CMake project that builds the plugin as a shared library (`plugin.so`). It reuses the exact compilers, C++ standard, and include paths from the original PyTNL-SPH build through a `build_info` module, ensuring ABI compatibility between the host extension and the dynamically loaded plugins.

#code1(
  [Part of the template used to generate `plugin.cpp`. EOS and integration scheme are fixed in the template; all other physics choices correspond directly to a VariantSpec field.],
  <sph_plugincpp_template>,
  ```cpp
  // ── 1. Device ────────────────────────────────────────────────────────────────
  {{DEVICE_INCLUDE}}
  {{DEVICE_USING}}

  // ── 2. Particle system configuration ─────────────────────────────────────────
  class ParticleSystemConfig {
      using RealType = {{PRECISION}};
      static constexpr int spaceDimension = {{SPACE_DIMENSION}};
      // ... index types, neighbour list type ...
  };

  // ── 3. SPH physics parameters ─────────────────────────────────────────────────
  template<typename DeviceT>
  class SPHParams {
  public:
      using KernelFunction    = TNL::SPH::KernelFunctions::{{KERNEL_TYPE}}<SPHConfig>;
      using DiffusiveTerm     = TNL::SPH::DiffusiveTerms::{{DIFFUSIVE_TERM}}<SPHConfig>;
      using ViscousTerm       = TNL::SPH::ViscousTerms::{{VISCOUS_TERM}}<SPHConfig>;
      using EOS               = TNL::SPH::EquationsOfState::TaitWeaklyCompressibleEOS<SPHConfig>;
      using BCType            = TNL::SPH::WCSPH_BCTypes::{{BC_TYPE}};
      using TimeStepping      = TNL::SPH::{{TIME_STEPPING}}<SPHConfig>;
      using IntegrationScheme = TNL::SPH::IntegrationSchemes::VerletScheme<SPHConfig>;
  };

  // ── 4. Top-level model alias ──────────────────────────────────────────────────
  using VariantModel = TNL::SPH::WCSPH_DBC<ParticlesSys, SPHParams<Device>>;

  // ── 5. C ABI entry points ─────────────────────────────────────────────────────
  extern "C" {
      pytnl_sph::ISimulation* sph_create()
          { return new pytnl_sph::ConcreteSimulation<VariantModel>("{{VARIANT_ID}}"); }
      void    sph_destroy(pytnl_sph::ISimulation* p) { delete p; }
      const char* sph_variant_id() { return "{{VARIANT_ID}}"; }
  }
  ```,
)

==== Build and cache

Compiled plugins are stored in a per-user cache directory (`~/.cache/pytnl_sph/` by default, configurable via an environment variable). Each variant occupies its own subdirectory containing the generated sources and the compiled shared library:

#code1(
  [Cache directory layout for a single compiled SPH variant. The `build/` subdirectory contains CMake artefacts and the final shared library.],
  <sph_cache_layout>,
  ```
  ~/.cache/pytnl_sph/
    wcsph_dbc_2d_cuda_float_dbc_molteni_artificial/
      plugin.cpp
      CMakeLists.txt
      build/
        plugin.so
  ```,
)

When a variant is requested, the system first checks whether `plugin.so` already exists in the cache. On a cache hit, the plugin is loaded immediately with negligible overhead. On a cache miss, the system generates the sources, invokes CMake to configure and build the project, and stores the result. Compilation output is streamed to the user in real time so that build progress and any errors are immediately visible.

==== Plugin loading and virtual dispatch

The compiled `plugin.so` is loaded into the Python process via `dlopen` with `RTLD_NOW | RTLD_LOCAL`. The `RTLD_NOW` flag ensures all symbols are resolved at load time, surfacing linking errors immediately. The `RTLD_LOCAL` flag keeps the plugin's symbols private, allowing multiple variants to coexist in a single process without symbol conflicts.

Communication between the host extension module and the plugin proceeds through a pure virtual #cpp interface `ISimulation`. This interface uses only simple types (`float`, `int`, `std::string`) --- no TNL types cross the ABI boundary.

The plugin's `sph_create()` function returns a pointer to a `ConcreteSimulation<Model>`, which implements `ISimulation` through composition: it holds the fully-templated `SPHMultiset_CFD<Model>` as a member and forwards each virtual method call to the corresponding method on it.

// TODO: briefly explain _why_ composition is preferred over inheritance here --- is it specifically the CUDA device-side vtable issue, or something else? Clarify for the reader.
// OR: Do not include the paragrapth about composition at all...
// Inheriting from both `ISimulation` and the large, non-polymorphic `SPHMultiset_CFD` would constitute problematic multiple inheritance — `SPHMultiset_CFD` has no virtual destructor and was not designed to be a base class — and the combination of virtual dispatch with CUDA device-side code creates further ABI hazards. Composition avoids both problems with no overhead.

The `ISimulation` interface exposes the individual phases of the simulation time step as separate methods: `performNeighborSearch()`, `interact()`, `computeTimeStep()`, `integrateVerletStep()`, and others --- following the original TNL-SPH design. All compute methods release the Python GIL during execution, ensuring that the interpreter is not blocked during long-running GPU or multi-threaded CPU computations.

==== User-facing API

From the user's perspective, the entire compilation and loading pipeline is hidden behind a single factory function. The user specifies the desired configuration through Python keyword arguments, and the factory either loads a cached plugin or triggers a compilation:

#code1(
  [Simplified example of the new API. The factory function handles code generation, compilation, caching, and plugin loading.],
  <sph_jit_usage_example>,
  ```python
  from pytnl_sph.jit import create_simulation, VariantSpec

  spec = VariantSpec(
        dimension=args.dimension,
        bc_type=BCType[args.bc_type],
        diffusive_term=DiffusiveTerm[args.diffusive_term],
        viscous_term=ViscousTerm[args.viscous_term],
        kernel=KernelType.WENDLAND,
        time_stepping=TimeStepping.VARIABLE,
        device=Device[args.device],
    )

  sph = create_simulation(spec=spec)

  sph.init(str(config_path))
  sph.writeProlog()
  while sph.runTheSimulation():
    sph.performNeighborSearch()
    sph.interact()
    sph.computeTimeStep()
    sph.integrateVerletStep()  # BCType::integrateInTime() is baked in
    sph.makeSnapshot()
    sph.measure()
    sph.updateTime()
  sph.write_epilog()
  ```,
)

@sph_jit_usage_example shows a simplified version of the final `run.py` script. The actual script still handles the runtime configuration generation and initial particle distribution setup, but all of that is done through Python functions rather than subprocess calls to separate scripts. The user interacts with a single Python script that handles everything from configuration to execution, without needing to touch any #cpp code or manually invoke the build system.

// TODO: compare the traditional three-step workflow (init.py → cmake build → run binary) with this single-script approach in a concise table or paragraph? The "PyTNL goals - workflow" section should set this up; verify it does.

==== Extending the time loop

// TODO: if I have time to do a real tested example, I should include it

While the loop is kept open and adjustable, the available operations are limited by the methods exposed by the `ISimulation` interface. This interface was designed only around the WCSPH-DBC model. More complex models may not fit the existing interface and will likely require additional methods to be added.

A second limitation concerns particle data access. The ISimulation ABI boundary intentionally passes only scalar values — simulation time, step index, and time-step size — to avoid TNL types crossing the .so boundary. As a consequence, there is no mechanism to read or write individual particle fields (density, velocity, pressure, distortion tensor) from the Python time loop.

Extending data access through ISimulation is non-trivial, because the interface works precisely by being decoupled from TNL types — it makes no assumptions about what the plugin contains, which is what keeps it general across all model variants. Returning TNL array types directly through a virtual method would reintroduce the model-specific type dependencies the boundary was designed to avoid.

A solution that preserves this decoupling is to expose only raw buffer descriptors: a pointer, an element count, a scalar type tag, and a device flag — all plain C types, safe across the ABI boundary. The host pytnl_sph module would then wrap each pointer into a PyTNL ArrayView, a non-owning view type that holds only a pointer and size without taking ownership of the underlying memory. This would let the plugin remain the sole owner of particle data while giving the Python side a first-class PyTNL object supporting the same operations as a regular array. ArrayView already exists in TNL's C++ layer with a bind(pointer, size) method; the remaining work would be exposing it to Python through PyTNL's bindings.

A more drastic alternative would be to lean more heavily into the code generation. Instead of the time loop being driven from Python, the user could provide a #cpp snippet that would be injected into the generated `plugin.cpp` and compiled together with the rest of the code. The Python side would then simply load and execute the prepared loop. In some ways, however, this would be a step back --- more an improvement to the existing scripts and tooling than an expansion of PyTNL. No actual binding of TNL-SPH code would be required.

// === Summary

// The code generation approach successfully addresses the combinatorial explosion inherent in pre-compiling all template variants. Instead of building 288 possible instantiations ahead of time, only the specific variant requested by the user is compiled, cached, and dynamically loaded. The compilation is fully automated and transparent to the user, who interacts with a single Python factory function.



// // TODO: add measured compilation times and compare with the traditional full-project rebuild to quantify the practical improvement

// The plugin architecture also enables the Python-side time loop, which is a qualitative improvement over the traditional workflow. Users gain the ability to insert arbitrary Python logic --- including the JIT-compiled buffer operations demonstrated earlier --- between simulation phases, without touching any #cpp code. This bridges the gap between the performance of a fully compiled solver and the flexibility of a scripting environment.

// // TODO: discuss whether user-defined functions (e.g., custom force terms) could be integrated into this pipeline --- either via the Numba/protocol approach from the previous chapter, or by extending the code generation to accept user-supplied C++ snippets. Evaluate trade-offs.
// // TODO: mention any current limitations or known issues (e.g., first-compilation latency, dependency on matching compiler versions, no Windows support?)

