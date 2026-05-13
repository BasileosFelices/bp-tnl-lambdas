#import "ctufit-thesis.typ": *
#import "@preview/fletcher:0.5.7" as fletcher: diagram, edge, node
#import "@preview/dashy-todo:0.1.3": todo

#let acknowledgment = [
  I would like to thank my supervisor, doc. Ing. Tomáš Oberhuber Ph.D., for his continuous guidance through the topic, for his support and insights that helped me overcome all the challanges.

  I will be forever grateful to my family for their unconditional support, not only in my studies but in all aspects of my life.

  Finally, I thank all my friends for all the, very much needed, pep~talks, encouragements and  all the fun times that keep me going.
]

#let declaration = [
  I hereby declare that the presented thesis is my own work and that I have cited all sources of information in accordance with the Guideline for adhering to ethical principles when elaborating an academic final thesis. I declare that I have used AI tools during the preparation and writing of my thesis. I have verified the generated content. I confirm that I am aware that I am fully responsible for the content of the thesis.
  \
  \
  I acknowledge that my thesis is subject to the rights and obligations stipulated by the Act No. 121/2000 Coll., the Copyright Act, as amended. In accordance with Section 2373(2) of Act No. 89/2012 Coll., the Civil Code, as amended, I hereby grant a non-exclusive authorization (license) to utilize this thesis, including all computer programs that are part of it or attached to it and all documentation thereof (hereinafter collectively referred to as the "Work"), to any and all persons who wish to use the Work. Such persons are entitled to use the Work in any manner that does not diminish the value of the Work and for any purpose (including use for profit). This authorization is unlimited in time, territory and quantity.
]

#let abstract-ENG = [
  This bachelors thesis focuses on exploring ways to expand the existing Python bindings for the Template Numerical Library (TNL). The goal was to design and implement an interface for TNL data structures that would allow usage of user-defined Python functions without sacrificing native performance.  The work first analyzes callback-based bindings of TNL higher-order functions through Nanobind and shows that ordinary Python callables are unsuitable for performance-critical execution because repeated crossings of the Python-C++ boundary introduce prohibitive overhead. The thesis therefore implements direct memory access for TNL arrays via the Python Buffer Protocol and DLPack. These protocols allow JIT-compiled CPU functions and CUDA kernels to operate directly on TNL-managed memory, shifting the interface design from callback passing to memory sharing. The approach is evaluated through benchmarks. An extension of the TNL-SPH solver further demonstrates a Python-driven just-in-time plugin system that generates, builds, caches, and loads selected simulation variants on demand. The results indicate that high-performance integration is better built on direct memory access than on emulating native C++ callback interfaces. The thesis briefly assesses possible strategies for a future Julia interface and identifies CxxWrap.jl as the most promising foundation for further development.
]

#let abstract-CZE = [
  Tato bakalářská práce se zabývá možnostmi rozšíření stávajícího rozhraní knihovny Template Numerical Library (TNL) v jazyce Python. Jejím cílem bylo navrhnout a implementovat rozhraní k datovým strukturám TNL, které umožní spouštět uživatelem v Pythonu definované funkce bez ztráty nativního výkonu. Práce nejprve analyzuje napojení funkcí vyššího řádu z TNL zpětným volání Python funkcí pomocí knihovny Nanobind a ukazuje, že provolávání Python objektů není pro výpočetně náročné operace vhodné, protože opakované přechody mezi prostředím Pythonu a C++ přinášejí nepřijatelnou režii. Práce proto implementuje přímý přístup k paměti TNL polí prostřednictvím protokolů Python Buffer Protocol a DLPack. Tyto protokoly umožňují, aby JIT kompilované funkce pro CPU i CUDA kernely pracovaly přímo s pamětí spravovanou v TNL strukturách. Rozhraní tak místo předávání samotných funkcí staví na sdílení paměti. Tento přístup je vyhodnocen pomocí benchmarků. Na rozšíření solveru TNL-SPH je dále předveden just-in-time pluginový systém řízený z Pythonu, který za běhu generuje, překládá, ukládá do cache a načítá vybrané varianty simulace. Výsledky ukazují, že výkonnou integraci je vhodnější stavět na přímém přístupu k paměti než na napodobování nativních callbackových rozhraní C++. V závěru práce jsou stručně posouzeny možné strategie budoucího rozhraní pro jazyk Julia; jako nejslibnější směr dalšího vývoje se přitom jeví vytvoření nového rozhraní s využitím knihovny CxxWrap.jl.
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
  keywords-CZE: "Template Numerical Library (TNL), PyTNL, CUDA, Python, C++, just-in-time (JIT) kompilace, Nanobind, Numba, Buffer protocol, DLpack, SPH, TNL-SPH, higher-order functions",
  keywords-ENG: "Template Numerical Library (TNL), PyTNL, CUDA, Python, C++, just-in-time (JIT) compilation, Nanobind, Numba, Buffer protocol, DLpack, SPH, TNL-SPH, higher-order functions",
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

#include "s_tool_intro.typ"

// == PyTorch, TensorFlow??

#include "s_higher_order_funcs.typ"

#include "s_transfer_protocols.typ"

= PyTNL expansion

#include "s_sph.typ"

// == PDLP Solver

// #todo(position: "inline")[How to include PDLP. It doesn't really tie in with the rest of the thesis, maybe try CVXPy and show the compatibility?]

#include "s_julia.typ"
