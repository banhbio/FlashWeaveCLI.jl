using FlashWeaveCLI
using Documenter

DocMeta.setdocmeta!(FlashWeaveCLI, :DocTestSetup, :(using FlashWeaveCLI); recursive=true)

makedocs(;
    modules=[FlashWeaveCLI],
    authors="banhbio <ban@kuicr.kyoto-u.ac.jp> and contributors",
    repo="https://github.com/banhbio/FlashWeaveCLI.jl/blob/{commit}{path}#{line}",
    sitename="FlashWeaveCLI.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://banhbio.github.io/FlashWeaveCLI.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/banhbio/FlashWeaveCLI.jl",
)
