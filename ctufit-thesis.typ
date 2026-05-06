#import "glossarium/glossarium.typ": gls-plural, gls-longplural, gls-short, gls-long, gls, glspl, Gls, Glspl
// #import "@preview/glossarium:0.5.7": gls-plural, gls-longplural, gls-short, gls-long, gls, glspl, Gls, Glspl

#let _code-common(
  caption,
  label,
  content,
  annotations: (),
  display-lang: true,
  inset: (right: 0.15em),
  lang-outset: (x: 0em, y: 0em),
  line-numbers: false,
  placement: none,
  ..pass
) = {
  // import "@preview/codly:1.3.0": *
  import "codly/codly.typ": *
  import "@preview/codly-languages:0.1.1": *
  show: codly-init.with()
  codly(
    annotations: annotations,
    annotation-format: none,
    display-icon: display-lang,
    display-name: display-lang,
    number-align: right + horizon,
    inset: inset,
    lang-outset: lang-outset,
    languages: codly-languages,
    zebra-fill: none,
    breakable: true
  )
  codly(number-format: if line-numbers { numbering.with("1") } else { none })

  [
    #show figure: set block(breakable: true)
    #figure(
      block(
        breakable: true,
        local(
          ..pass,
          content
        ),
      ),
      caption: caption,
      kind: raw,
      supplement: "Code listing",
      placement: placement,
    ) #label
  ]
}

#let code1(
  caption,
  label,
  code,
  ..common,
) = {
  _code-common(
    caption,
    label,
    ..common,
    code,
  )
}

#let cpp = box[C#h(-0.05em)++\u{2060}]

#let mcite(..labels) = {
  "[" 
  {
    // The show rule is isolated inside these curly braces
    show "[": none
    show "]": none
    labels.pos().map(l => cite(l)).join(", ")
  }
  "]"
}

#let code2(
  caption,
  label,
  code-lhs,
  code-rhs,
  columns: (auto, auto),
  lhs: (),
  rhs: (),
  ..common,
) = {
  // import "@preview/codly:1.3.0": *
  import "codly/codly.typ": *
  _code-common(
    caption,
    label,
    ..common,
    {
      grid(
        columns: columns,
        {
          local(
            ..lhs,
            code-lhs
          )
        },
        {
          local(
            ..rhs,
            code-rhs
          )
        },
      )
    }
  )
}

#let ctufit-thesis(
  title: "",
  author-full: "",
  author-surnames: "",
  author-given-names: "",
  department: "",
  study-program: "",
  specialization: "",
  supervisor: "",
  year: "",
  acknowledgment: "",
  declaration: "",
  declaration-place: "",
  declaration-date: datetime.today(),
  abstract-CZE: "",
  abstract-ENG: "",
  keywords-CZE: "",
  keywords-ENG: "",
  thesis-type: "bachelor", // Can be "bachelor", "master", or "dissertation"
  lang: "english", // Can be "czech", "english", or "slovak"
  bw: false, // Black and white mode
  twosided: true,
  body
) = {
  // author Oliver Tušla 2025
  // based on CTU FIT LaTex template
  // https://gitlab.fit.cvut.cz/theses-templates/FITthesis-LaTeX/

  set document(author: author-full, title: title)
  
  import "glossarium/glossarium.typ": make-glossary, register-glossary, print-glossary, gls, glspl
  // import "@preview/glossarium:0.5.7": make-glossary, register-glossary, print-glossary, gls, glspl

  /* Sizes
  https://latex-tutorial.com/changing-font-size/
  size	10pt	11pt	12pt
  \tiny	5	6	6
  \scriptsize	7	8	8
  \footnotesize	8	9	10
  \small	9	10	10.95
  \normalsize	10	10.95	12
  \large	12	12	14.4
  \Large	14.4	14.4	17.28
  \LARGE	17.28	17.28	20.74
  \huge	20.74	20.74	24.88
  \Huge	24.88	24.88	24.88
  */
  let font_size = 11pt
  let size_tiny = 6pt
  let size_scriptsize = 8pt
  let size_footnotesize = 9pt
  let size_small = 10pt
  let size_large = 12pt
  let size_Large = 14.4pt
  let size_LARGE = 17.28pt
  let size_huge = 20.74pt
  let size_Huge = 24.88pt
  // https://latexref.xyz/_005cfbox-_0026-_005cframebox.html
  let fboxsep = 3pt
  let baselineskip = 13.6pt
  // setstretch{1.25} https://github.com/LaTeX-Package-Repositories/setspace/blob/main/setspace.sty
  let onehalspacing = 1.25

  set text(
    font: "New Computer Modern",
    size: font_size,
  )

  /* Colors */
  let heading-number-background = rgb(199, 219, 241) // headbackgroundgray
  let head-gray = rgb(50%, 50%, 50%) //headgray
  let ctu-blue = rgb(0, 122, 195)

  // TODO footskip??
  let page-margin = if twosided {
    (top: 46mm, bottom: 40mm, inside: 47mm, outside: 32.5mm)
  } else {
    (top: 46mm, bottom: 40mm, left: 39.5mm, right: 40mm)
  }
  set page(margin: page-margin)

  let ref-box(it) = {
    if twosided {
      it
    } else {
      box(
        outset: (x: 0.5pt, y: 194% - 1em),
        stroke: 0.5pt + red,
        it,
      )
    }
  }

  // https://github.com/typst/typst/discussions/2585
  // show ref: it => context {
  //   // TODO handle other forms
  //   if it.element != none and it.element.func() == figure and it.form == "normal" {
  //     let fig = it.element
  //     let loc = it.element.label
  //     let last-chapter = query(
  //       selector(heading.where(level: 1)).before(loc)
  //     ).last()
  //     let figures-in-chapter = query(
  //       selector(figure.where(kind: fig.kind))
  //         .after(
  //           locate(last-chapter.label)
  //         )
  //         .before(loc)
  //     )
  //     link(
  //       it.target,
  //       {
  //         it.element.supplement
  //         [ ]
  //         numbering(
  //           fig.numbering,
  //           counter(heading.where(level: 1)).get().at(0),
  //           figures-in-chapter.len(),
  //         )
  //       }
  //     )
  //   } else {
  //     it
  //   }
  // }
  show ref: it => ref-box(it)
  show link: it => ref-box(it)
  show cite: it => ref-box(it)

  let text-lang = if lang == "english" {
    "en"
  } else if lang == "czech" {
    "cs"
  } else if lang == "slovak" {
    "sk"
  } else {
    panic("Unsupported language")
  }
  set text(lang: text-lang)

  // Language-dependent strings
  let thesis-type-str = {
    if thesis-type == "bachelor" {
      if lang == "czech" { "Bakalářská práce" } 
      else if lang == "slovak" { "Bakalárska práca" } 
      else { "Bachelor's thesis" }
    } else if thesis-type == "master" {
      if lang == "czech" { "Diplomová práce" } 
      else if lang == "slovak" { "Diplomová práca" } 
      else { "Master's thesis" }
    } else if thesis-type == "dissertation" {
      "Dissertation thesis"
    } else {
      panic("Thesis type not specified. Use 'bachelor', 'master', or 'dissertation'")
    }
  }

  let intro-label = {
    if lang == "czech" or lang == "slovak" { "Úvod" }
    else { "Introduction" }
  }

  let conclusion-label = {
    if lang == "czech" { "Závěr" }
    else if lang == "slovak" { "Záver" }
    else { "Conclusion" }
  }

  let university-str = {
    if lang == "czech" or lang == "slovak" { "České vysoké učení technické v Praze" } 
    else { "Czech Technical University in Prague" }
  }

  let faculty-str = {
    if lang == "czech" or lang == "slovak" { "Fakulta informačních technologií" }
    else { "Faculty of Information Technology" }
  }

  let supervisor-label = {
    if lang == "czech" { "Vedoucí" } 
    else if lang == "slovak" { "Vedúci" } 
    else { "Supervisor" }
  }

  let studyprogram-label = {
    if lang == "czech" { "Studijní program" }
    else if lang == "slovak" { "Študijný program" }
    else { "Study program" }
  }

  let specialization-label = {
    if lang == "czech" { "Specializace" }
    else if lang == "slovak" { "Špecializácia" }
    else { "Specialization" }
  }

  let citation-label = {
    if lang == "czech" { "Odkaz na tuto práci" } 
    else if lang == "slovak" { "Odkaz na túto prácu" } 
    else { "Citation of this thesis" }
  }

  let all-rights-reserved-label = {
    if lang == "czech" { "Všechna práva vyhrazena." } 
    else if lang == "slovak" { "Všetky práva vyhradené." } 
    else { "All rights reserved." }
  }

  let acknowledgment-heading = {
    if lang == "czech" { "Poděkování" }
    else if lang == "slovak" { "Poďakovanie" }
    else { "Acknowledgments" }
  }

  // TODO use
  let listing-label = {
    if lang == "czech" or lang == "slovak" { "Výpis kódu" } 
    else { "Code listing" }
  }

  let lol-label = {
    if lang == "czech" { "Seznam výpisů kódu" } 
    else if lang == "slovak" { "Zoznam výpisov kódu" } 
    else { "List of code listings" }
  }

  let list-of-tables-label = {
    if lang == "czech" { "Seznam tabulek" } 
    else if lang == "slovak" { "Zoznam tabuliek" } 
    else { "List of tables" }
  }

  let list-of-images-label = {
    if lang == "czech" { "Seznam obrázků" } 
    else if lang == "slovak" { "Zoznam obrázkov" } 
    else { "List of images" }
  }

  let declaration-label = {
    if lang == "czech" { "Prohlášení" } 
    else if lang == "english" { "Declaration" } 
    else { "Vyhlásenie" }
  }

  let abbreviation-label = {
    if lang == "czech" { "Seznam zkratek" } 
    else if lang == "english" { "List of abbreviations" } 
    else { "Zoznam skratiek" }
  }

  let chapter-label = {
    if lang == "czech" or lang == "slovak" { "Kapitola" } 
    else { "Chapter" }
  }

  let copyright-text = {
    if lang == "czech" { 
      "Tato práce vznikla jako školní dílo na Českém vysokém učení technickém v Praze, Fakultě informačních technologií. Práce je chráněna právními předpisy a mezinárodními úmluvami o právu autorském a právech souvisejících s právem autorským. K jejímu užití, s výjimkou bezúplatných zákonných licencí a nad rámec oprávnění uvedených v Prohlášení, je nezbytný souhlas autora."
    } else if lang == "slovak" {
      "Táto práca vznikla ako školské dielo na FIT ČVUT v Prahe. Práca je chránená medzinárodnými predpismi a zmluvami o autorskom práve a právach súvisiacich s autorským právom. Na jej využitie, s výnimkou bezplatných zákonných licencií, je nutný súhlas autora."
    } else {
      "This thesis is school work as defined by Copyright Act of the Czech Republic. It has been submitted at Czech Technical University in Prague, Faculty of Information Technology. The thesis is protected by the Copyright Act and its usage without author's permission is prohibited (with exceptions defined by the Copyright Act)."
    }
  }

  let title-page = {
    page(
      margin: (left: 67mm, top: 80mm, right: 40mm, bottom: 35mm),
      header: none,
      footer: none,
      background: none
    )[
      #set align(left)
      #set par(spacing: 0pt)

      #image("assets/logoCVUT.svg", width: 3cm)

      // source: ruler bro
      #v(32mm)

      #text(size: size_huge, weight: "bold")[
        #set par(leading: baselineskip * onehalspacing)
        #upper(title)
      ]
      
      #v(25.5mm)
      
      #text(size: size_large, weight: "bold", author-full)
      
      #v(1fr)

      #thesis-type-str \
      #faculty-str \
      #university-str \
      #department \
      #studyprogram-label: #study-program \
      #specialization-label: #specialization \
      #supervisor-label: #supervisor \
      // TODO support Czech and Slovak
      #declaration-date.display("[month repr:long] [day], [year]")
    ]
  }

  title-page

    {
     pagebreak()
     page(margin: 0pt)[
      #image("assets/spelifil-assignment.pdf", width: 100%, height: 100%)
    ]
   }

  {
    pagebreak()
    v(1fr)
    [
      #university-str \
      #faculty-str \
      #sym.copyright #year #author-full. #all-rights-reserved-label \
      #text(style: "italic", copyright-text) \
      \

      #citation-label: #author-full. #text(style: "italic", title). #thesis-type-str. #university-str, #faculty-str, #year.
    ]
  }

  counter(page).update(2)
  set page(
    footer: context {
      set align(center)
      set text(fill: head-gray, weight: "bold")
      counter(page).display()
    },
    numbering: "i",
  )
  set par(
    spacing: 0.65em, // = default leading
    justify: true,
  )
  
  {  
    pagebreak()
    show heading: none
    heading(acknowledgment-heading)

    // apparently, LaTex treats the acknowledgment
    // as a paragraph and indents it
    // https://tex.stackexchange.com/questions/152582/why-is-the-minipage-indented-on-the-left
    // TODO I still need to shift it up somehow
    align(horizon,
      pad(
        left: 1.5em, // == first-line-indent
        box(
          width: 70% + 1.5em,
          inset: (top: -100%),
          text(
            style: "italic",
            acknowledgment,
          ),
        ),
      )
    )
    pagebreak()
  }
  
  show heading: set par(first-line-indent: 0pt)
  show heading: set text(fill: ctu-blue)
  // I like this but the official template doesn't do it
  show outline: set heading(bookmarked: true)
  show outline.entry.where(
    level: 1
  ): it => {
    if it.element.func() == heading {
      set text(fill: ctu-blue)
      it
    } else {
      it
    }
  }

  show outline.entry: entry => {
    ref-box(entry)
  }

  set list(
    marker: (
      rect(
        fill: ctu-blue,
        height: 0.33em,
        width: 0.67em
      ),
      rect(
        fill: ctu-blue,
        height: 0.225em,
        width: 0.45em
      ),
      text(
        fill: ctu-blue,
        sym.ast,
      ),
      text(
        fill: ctu-blue,
        sym.dot,
      ),
    ),
  )

  let list-depth = counter("list-depth")
  // https://github.com/typst/typst/issues/4520
  show list.item: it => context {
    let depth = list-depth.get().at(0)
    let marker = list.marker.at(
        calc.min(
          depth,
          list.marker.len() - 1,
        )
      )
    list-depth.update(n => n + 1)
    // TODO left margin
    // TODO spacing
    // TODO handle nested
    let margin = 0.5em
    // let baseline = measure()[A].height
    pad(
      top: par.spacing / 1.5, // layman's solution for padding the list as a whole
      // bottom: par.spacing / 2, // show list: doesn't work for some reason
      grid(
        columns: (auto, 1fr),
        column-gutter: margin,
        box(
          // baseline: baseline,
          baseline: 175%,
          inset: (left: calc.max(((2 - depth) / 3 * margin), 0pt)),
          // inset: (left: margin),
          marker,
        ),
        it.body,
      )
    )
    list-depth.update(n => n - 1)
  }
  // show list.item: it => context { it }
  // show list: it => {set text(fill: red);it}

  {
    show heading: set align(right)
    show heading: set block(below: 9mm)
    v(1fr)
    heading(declaration-label)
    let decl-pref = if lang == "czech" or lang == "slovak" { "V " + declaration-place + " dne" }
                    else { "In " + declaration-place + " on" }
    [
      #declaration \
      \
      \
      #decl-pref #declaration-date.display("[month repr:long] [day], [year]")
    ]
    pagebreak()
  }

  set par(
    // TODO proper size
    first-line-indent: 1.5em,
  )

  let abstract(ab-heading, ab-body, kw-label, kw-text) = {
    // TODO heading font size
    show heading: set block(below: 9mm)
    heading(outlined: false, ab-heading)
    
    ab-body
    linebreak()
    v(6.5mm)

    block({
      text(fill: ctu-blue, weight: "bold", kw-label)
      h(1em)
      kw-text
    })
  }
  let czech-abstract = abstract("Abstrakt", abstract-CZE, "Klíčová slova", keywords-CZE)
  let english-abstract = abstract("Abstract", abstract-ENG, "Keywords", keywords-ENG)
  let (first-abstract, second-abstract) = if lang == "english" {
      (english-abstract, czech-abstract)
    } else {
      (czech-abstract, english-abstract)
    }
  first-abstract
  // pagebreak()
  v(3em)
  second-abstract

  show heading.where(level: 1): set align(right)

  {
    show heading.where(level: 1): set block(below: 11mm)
    pagebreak()
    // context {
    //   // let bib-heading = query(selector(heading)).find(h => h.body == [Bibliography])
    context outline(
      depth: 3,
      target: selector(heading)
        .after(here())
        // .before(locate(bib-heading.label))
    )
    // }
    pagebreak()

    outline(
      target: figure.where(kind: raw),
      title: lol-label
    )
    v(1.5em) // TODO
    outline(
      target: figure.where(kind: table),
      title: list-of-tables-label,
    )
    v(1.5em)
    outline(
      target: figure.where(kind: image),
      title: list-of-images-label,
    )
    pagebreak()
  }

  heading(abbreviation-label, outlined: false)
  show: make-glossary
  import "acronyms.typ": entry-list
  register-glossary(entry-list)
  // TODO user-print-title
  print-glossary(entry-list)

  let chapter-heading-below = 27.5mm
  show heading: set block(below: 1.2em) // = default par spacing
  show heading.where(level: 1): set text(size: size_Huge)
  show heading.where(level: 1): set block(below: chapter-heading-below)
  show heading.where(level: 1): set heading(supplement: chapter-label)
  set page(
    header: context {
      set text(fill: head-gray, weight: "bold")
      let following-chapters = query(
        selector(heading.where(level: 1)).after(here())
      )
      if (following-chapters.len() == 0
          or following-chapters.first().location().page() != here().page()) {
        let latest-label = {
          let last-heading = query(
            selector(heading).before(here())
          ).rev().find(h => h.level <= 2)
          let following-headings = query(
            selector(heading.where(level: 2)).after(here())
          ).filter(h => h.location().page() == here().page())
          if following-headings.len() != 0 {
            following-headings.last().body
          } else if last-heading != none {
            last-heading.body
          } else {
            ""
          }
        }
        let previous-chapters = query(
          selector(heading.where(level: 1)).before(here())
        )
        let (left, right) = {
          if twosided and calc.even(counter(page).get().first()) {
            let tmp = if previous-chapters.len() != 0 {
                previous-chapters.last().body
              } else {
                latest-label
              }
            (counter(page).display(), tmp)
          } else {
            (latest-label, counter(page).display())
          }
        }
        grid(
          columns: (1fr, auto),
          left,
          right,
        )
        v(-1em) // TODO how do you change the size of the header!?
      }
    },
    footer: context {
      let chapters = query(selector(heading.where(level: 1)).before(here()))
      if (chapters.len() != 0
          and chapters.last().location().page() == here().page()) {
        set align(center)
        set text(fill: head-gray, weight: "bold")
        counter(page).display()
      }
    },
    numbering: "1",
  )

  // {
  //   page(header: [])[]
  //   page(header: [])[]
  // }
  pagebreak()
  counter(page).update(1)
  {
    heading(intro-label)
    include "introduction.typ"
  }

  {
    set heading(numbering: "1.1")
    show heading: it => {
      set text(fill: black)
      let number = counter(heading).display(it.numbering)
      if it.level == 1 {
        // Ensure chapter headings start at the top of a page without adding blank pages.
        pagebreak(weak: true)
        if twosided {
          // fix this to leave empty pages
          // pagebreak(to: "odd")
        }
        {
          set text(size: size_LARGE, weight: "bold")
          let line-thickness = 0.25em
          // https://en.m.wikipedia.org/wiki/Pica_(typography)
          let pc = (400 / 2409) * 1in
          // context measure(text(size: size_LARGE, weight: "bold", "x"))
          let ex = 11.85pt
          grid(
            align: bottom,
            columns: (1fr, auto),
            column-gutter: 0.5 * ex + line-thickness * 2,
            row-gutter: 6mm,
            box(
              baseline: -line-thickness / 2,
              line(
                length: 100%,
                stroke: (
                  dash: (array: ("dot", pc / 2, "dot", pc / 2)),
                  paint: heading-number-background,
                  thickness: line-thickness,
                ),
              ),
            ),
            [#chapter-label #number],
            grid.cell(
              colspan: 2,
              text(
                fill: ctu-blue,
                size: size_Huge,
                it.body,
              )
            ),
          )
        }
      } else {
        let size = if it.level <= 3 { size_Large } else { size_large }
        set text(size: size)
        let number-box = if it.level == 2 {
            let inset = 3pt
            box(
              baseline: inset,
              fill: heading-number-background,
              inset: inset, // fboxsep
              number,
            )
          } else { number }
        let body = text(fill: ctu-blue, it.body)
        block[#number-box#h(1em)#body]
      }
    }

    show figure: it => {
      let b = if it.kind == raw {
        block(
          breakable: true,
          width: 100%,
          {
            v(it.gap) 
            it.body
            v(it.gap) 
            it.caption
          },
        )
      } else if it.kind == table {
        box(
          width: 100%,
          grid(
            // align: left,
            rows: (auto),
            row-gutter: it.gap,
            it.caption,
            {
              h(1fr)
              box(it.body)
              h(1fr)
            },
          )
        )
      } else {
        box(
          width: 100%,
          grid(
            // align: left,
            rows: (auto),
            row-gutter: it.gap,
            {
              h(1fr)
              box(it.body)
              h(1fr)
            },
            it.caption
          )
        )
      }
      if it.placement == none {
        b
      } else {
        place(
          it.placement,
          float: true,
          b
        )
      }
      par[] // This is currently required to keep
      // consecutive paragraphs.
      // This issues says it's fixed but I don't think so
      // https://github.com/typst/typst/issues/311
    }
    show figure: set align(left)
    show figure.where(kind: table): set figure.caption(position: top)
    set figure.caption(separator: [ ])
    set figure(numbering: "1.1")
    show figure.caption: it => context {
      // let last-chapter = query(
      //   selector(heading.where(level: 1)).before(here())
      // ).last()
      // let figures-in-chapter = query(
      //   selector(figure.where(kind: it.kind))
      //     .after(
      //       locate(last-chapter.label)
      //     )
      //     .before(here())
      // )
      
      let rect-dim = 0.73em
      // let baseline = (measure[A].height - rect-dim) / 2
      set align(left) // this is needed for floating figures!?
      box(
        // baseline: baseline,
        rect(
          fill: ctu-blue,
          width: rect-dim,
          height: rect-dim,
        )
      )
      h(0.67em)
      text(
        weight: "bold",
        {
          upper(it.supplement.text.at(0))
          it.supplement.text.slice(1)
          [ ]
          it.counter.display()
          // numbering(
          //   it.numbering,
          //   counter(heading.where(level: 1)).get().at(0),
          //   figures-in-chapter.len(),
          // )
          it.separator
        },
      )
      it.body
    }

    body
  }
  // {
  //   page(header: [])[]
  // }
  set heading(numbering: none)
  {
    pagebreak()
    heading(conclusion-label)
    include "conclusion.typ"
  }
  {
    pagebreak()
    bibliography(
      "works.bib",
      // style: "/assets/ieee-with-url.csl",
      style: "/assets/iso690-numeric-en.csl",
      // style: "iso-690-numeric"
      // style: "institute-of-electrical-and-electronics-engineers",
      // style: "association-for-computing-machinery",
      // style: "american-psychological-association",
    )
    v(1fr)
    align(center, text(fill: head-gray)[Proudly built with Typst])
  }
  

  set text(size: font_size)
  pagebreak()
  heading[Contents of the attachment]
  include "attachment.typ"
}