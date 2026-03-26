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


= Introduction to TNL

= Python computation libraries

== Requirements and considerations

== Numpy

== CuPy

== JAX

== Polars

// https://docs.pola.rs/user-guide/expressions/user-defined-python-functions/#processing-a-whole-series-with-map_batches




== PyTorch, TensorFlow??

= Higher order functions and just-in-time compilation

== TNL Functions

== PyTNL and Nanobind

== Numba

== NVRTC 


= Accessing C++ managed memory

== Python Array API Standard

== Python Buffer protocol

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

DLPack is currently the recommended primary protocol for interchanging the array data between libraries. It's primary advantage compared to both Buffer protocol and CAI is the device support. The protocol can be implemented for CPU, GPU and even multi device array types. 

Of course, it's up to the discretion of the consumer to determine if it is able to actually work with the incoming array. It's possible to support the interface while keeping support for only one type of device. 

// https://dmlc.github.io/dlpack/latest/index.html

...

= Demonstration

== PDLP Solver

== SPH???????

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

