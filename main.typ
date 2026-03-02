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
  declaration-date: datetime(year: 2026, month: 5, day: 15),
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

= Dynamic compiling of lambda functions

intro

== Lambda functions in TNL

TNL exposes several useful higher order functions that extends users options for modifying the TNl data structures using their own lambda functions. Thanks to context capturing and working with #cpp iterators, they provide a fairly powerful API. One such example might be the `ParallelFor` function.

=== #cpp lambda functions

// TODO: quick c++ overview of lambda functions

=== Python lambda functions

// TODO: quick python lambda function overview

=== Utilizing python lambda functions in PyTNL

The goal is reasonably simple from the API perspective. PyTNL should allow users to write some kind of lambda functions and allow executing them upon PyTNL exposed data structures. Ideally we would expose already existing higher order functions from TNL.

The main challenge of binding a higher order function such as `ParallelFor` is the ability to pass a Python Lambda function into 

Binding a higher order function such as `ParallelFor` faces two big challenges:

+ Passing a Python Lambda function into the #cpp codebase and executing it from there.
+ Allowing the context capture. As above, we would be capturing Python objects and subsequently passing them once again into the #cpp runtime. 



== Tools


=== Numba

To battle the performance issues of Python code, I tried to explore JIT compilation options. If we could precompile the python lambdas and separate it from the interpreter, we could achieve significant speed increase. 
// TODO some source showing JIT in Numba actually speeds something up.

However, even JIT Numba precompiled functions are still passed through the bindings as a Python object and is still pretty slow.

I had to eliminate Python all together and that was possible with numbas Cfuncs. The bindings had to be adjusted to accept a pointer straight to the function instead of `nb::callable`. This truly did speed things up. However two problems remained. Context capture sucked and even more so, this function could only be executed by the CPU. In order to run the code on device, we would need a differently compiled kernel.

=== Numba CUDA

And that's where Numba CUDA was supposed to come in. However, I quickly discovered cuda has no cfunc equivalent. And Numba CUDA functions could not be passed by pointers to the bindings.
// TODO: What about nb::callable???

=== Cupy, Cuda CORE - NRVTC

