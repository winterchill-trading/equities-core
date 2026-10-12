(lang dune 3.17)

(name equities-core)

(generate_opam_files true)

(license MIT)

(maintainers "winterchill-trading")

(authors "winterchill-trading")

(source
 (github winterchill-trading/equities-core))

(package
 (name equities-core)
 (synopsis
  "Shared semantics for US equities, options and futures venue simulators")
 (depends
  (ocaml
   (>= 5.2))
  dune
  core
  fixed-decimal
  exchange-core
  ppx_jane))
