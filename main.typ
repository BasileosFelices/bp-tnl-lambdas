#import "ctufit-thesis.typ": *
#import "@preview/fletcher:0.5.7" as fletcher: diagram, edge, node

#let cpp = [C++]

// TODO
#let acknowledgment = [
  TODO: Poděkování
]

#let declaration = [
  I hereby declare that the presented thesis is my own work and that I have cited all sources of information in accordance with the Guideline for adhering to ethical principles when elaborating an academic final thesis. I declare that I have used AI tools during the preparation and writing of my thesis. I have verified the generated content. I confirm that I am aware that I am fully responsible for the content of the thesis.
  \
  \
  I acknowledge that my thesis is subject to the rights and obligations stipulated by the Act No. 121/2000 Coll., the Copyright Act, as amended. In accordance with Section 2373(2) of Act No. 89/2012 Coll., the Civil Code, as amended, I hereby grant a non-exclusive authorization (license) to utilize this thesis, including all computer programs that are part of it or attached to it and all documentation thereof (hereinafter collectively referred to as the "Work"), to any and all persons who wish to use the Work. Such persons are entitled to use the Work in any manner that does not diminish the value of the Work and for any purpose (including use for profit). This authorization is unlimited in time, territory and quantity.
]

#let abstract-ENG = [
  TODO
]

#let abstract-CZE = [
  TODO
]

#show: ctufit-thesis.with(
  title: "Interfaces for TNL data structures and algorithms in Python and Julia",
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

= Introduction

== CUDA, GPU computations

// short intro

== Introduction to TNL

== PyTNL

// == PyTorch, TensorFlow??

= Higher order functions and just-in-time compilation

== TNL Functions

== PyTNL and Nanobind

== Numba <numba_introduction>

== NVRTC <nvrtc_introduction>

== Benchmark <function_calling_from_cpp_benchmark>

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

== Other Python libraries

=== CuPy

=== Polars

// https://docs.pola.rs/user-guide/expressions/user-defined-python-functions/#processing-a-whole-series-with-map_batches

=== NumPy

// TODO: mention inspiration from some libraries described above?
=== JAX

#include "s_transfer_protocols.typ"

= Demonstration

#include "s_sph.typ"

== PDLP Solver



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
