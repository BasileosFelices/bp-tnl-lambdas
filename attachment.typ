#import "@preview/treet:0.1.1": *


#set text(font: "DejaVu Sans Mono", size: 9pt)
#let dots() = box(width: 1fr, repeat[.])

#tree-list[
  - README.md #dots() attachment overview
  - bp-cdu-code/ #dots() ch.2 benchmark + nanobind demo
  - py-tnl-lp-sph/ #dots() PyTNL fork with protocol work
  - testbed-pytnl/ #dots() ch.3 protocol PyTNL benchmark
  - tnl-lambdatests/ #dots() early lambda/NVRTC experiments
  - tnl-sph-py-tnl/ #dots() TNL-SPH fork with PyTNL integration
]
