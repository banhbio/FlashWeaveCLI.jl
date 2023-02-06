module FlashWeaveCLI

using Comonicon
using Distributed
using JSON
@everywhere using FlashWeave

"""

# Args

- `input...`: 

# Options

- `-p, --procs <int=1>`: specify the number of workers in Julia's built-in parallel infrastructure. `default = 1`
- `-o, --output <path>`: is the path to the output file. File extension should be one of the $(FlashWeave.valid_net_formats). `Required`
- `--meta-data <path>`: is the optional path to the meta data.
- `--header <headers>`: are the names of variable columns in `input`. should be in the form of `[name1,name2,...]`.
- `--meta-mask <masks>`: are the true/false masks indicating which variables are meta variables. should be in the form of `[true,false,...]`.
- `--max-k <int=3>`: is the maximum size of conditioning sets, high values can lead to the removal of more spurious edgens, but may also strongly increase runtime and reduce statistical power. `max_k=0` results in no conditioning (univariate mode).
- `--alpha <float=0.01>`:is the statistical significance threshold at which individual edges are accepted.
- `--conv <float=0.01>`: is the convergence threshold, e.g. if `conv=0.01` assume convergence if the number of edges increased by only 1% after 100% more runtime (checked in intervals).
- `--prec <int=32>`: is the precision in bits to use for calculations (16, 32, 64 or 128).
- `--max-tests <int=Int(1e6)>`: is the maximum number of conditional tests that is performed on a variable pair before association is assumed.
- `--hps <int=5>`: is the reliability criterion for statistical tests when `sensitive=false`.
- `--n-obs-min <int=-1>`: don't compute associations between variables having less reliable samples (non-zero samples if `heterogeneous=true`) than this number. `-1`: automatically choose a threshold.
- `--time-limit <float64=-1>`: if feed-forward heuristic is active, determines the interval (seconds) at which neighborhood information is updated.
- `--update_interval <float64=30>`: if `verbose=true`, determines the interval (seconds) at which network stat updates are printed.
- `--parallel-mode <auto>`: specify parallel mode.
- `--otu-data-key <otu_data>`: is HDF5 keys to access data sets with OTU counts in a JLD2 file. If a data item is absent the corresponding key should be 'nothing'. See FlashWeave.jl docs for additional information.
- `--otu-header-key <otu_header>`: is HDF5 keys to access data sets with OTU names in a JLD2 file. If a data item is absent the corresponding key should be 'nothing'. See FlashWeave.jl docs for additional information.
- `--meta-data-key <meta_data>`: is HDF5 keys to access data sets with Meta variables in a JLD2 file. If a data item is absent the corresponding key should be 'nothing'. See FlashWeave.jl docs for additional information.
- `--meta-header-key <meta_header> `: is HDF5 keys to access data sets with Meta variable names in a JLD2 file. If a data item is absent the corresponding key should be 'nothing'. See FlashWeave.jl docs for additional information.

# Flags

- `--no-sensitive`: suppress fine-grained association prediction (FlashWeave-S, FlashWeaveHE-S),  `sensitive=false` results in the `fast` modes (FlashWeave-F, FlashWeaveHE-F).
- `--heterogeneous`: enable heterogeneous mode for multi-habitat or -protocol data with at least thousands of samples (FlashWeaveHE).
- `--no-feed-forward`: suppress feed-forward heuristic.
- `--no-fast-elim`: suppress feed-forward heuristic.
- `--no-normalize`: suppress normalization. If `normalize=true`, automatically choose and perform data normalization method (based on `sensitive` and `heterogeneous`).
- `-q, --quiet`: suppress progress information.
- `--track-rejections`: store for each discarded edge, which variable set lead to its exclusion (can be memory intense for large networks).
- `--transposed`: if `true`, rows of `data` are variables and columns are samples.
- `--no-make-sparse`: suppress a sparse data representation (should be left at enable in almost all cases).
- `--no-make-onehot`: suppress a sparse data representation (should be left at enable in almost all cases).
- `--no-FDR`: suppress False Discovery Rate correction (Benjamini-Hochberg method) on pairwise associations.
- `--cache-pcor`:
- `--no-share-data`: suppress sharing input data (instead of copying) if local parallel wokers are detected. 
"""
@main function flashweave(input...;
                procs::Int=1,
                output=nothing,
                meta_data=nothing,
                otu_data_key="otu_data",
                otu_header_key="otu_header",
                meta_data_key="meta_data",
                meta_header_key="meta_header",
                no_sensitive::Bool=false,
                heterogeneous::Bool=false,
                max_k::Int=3,
                alpha::Float64=0.01,
                conv::Float64=0.01,
                header=nothing,
                meta_mask=nothing,
                no_feed_forward::Bool=false,
                no_fast_elim::Bool=false,
                no_normalize::Bool=false,
                track_rejections::Bool=false,
                quiet::Bool=false,
                transposed::Bool=false,
                prec::Int=32,
                no_make_sparse::Bool=false,
                no_make_onehot::Bool=false,
                max_tests=Int(10e6),
                hps::Int=5,
                no_FDR::Bool=false,
                n_obs_min::Int=-1,
                cache_pcor::Bool=false,
                time_limit::Float64=-1.0,
                update_interval::Float64=30.0,
                parallel_mode="auto",
                no_share_data::Bool=false,
                )

    if isempty(input)
        cmd_error("Empty input.")
    end

    if isnothing(output)
        cmd_error("Output not specified.")
    end

    # early return
    file_ext = splitext(output) |> last
    if endswith.(Ref(file_ext), FlashWeave.valid_net_formats) |> any |> !
        cmd_error("$(file_ext) not a valid output format. Choose one of $(FlashWeave.valid_net_formats)")
    end

    # parse input as json (https://stackoverflow.com/questions/44194951/what-is-the-equivalent-of-pythons-ast-literal-eval-in-julia)
    if !isnothing(header)
        header = JSON.parse(header)
        if header isa Vector
            cmd_error("Invaild --header format.")
        end
    end

    if !isnothing(meta_mask)
        meta_mask = JSON.parse(meta_mask)
        if meta_mask isa Vector
            cmd_error("Invaild --meta-mask format.")
        end
    end

    i = if length(input) == 1
        first(input)
    else
        [input...]
    end

    

    addprocs(procs)
    try
        netw_results = learn_network(i, meta_data;
                otu_data_key=otu_data_key,
                otu_header_key=otu_header_key,
                meta_data_key=meta_data_key,
                meta_header_key=meta_header_key,
                verbose=!quiet,
                sensitive=!no_sensitive,
                heterogeneous=heterogeneous,
                max_k=max_k,
                alpha=alpha,
                conv=conv,
                header=header,
                meta_mask=meta_mask,
                feed_forward=!no_feed_forward,
                fast_elim=!no_fast_elim,
                normalize=!no_normalize,
                track_rejections=track_rejections,
                transposed=transposed,
                prec=prec,
                make_sparse=!no_make_sparse,
                make_onehot=!no_make_onehot,
                max_tests=max_tests,
                hps=hps,
                FDR=!no_FDR,
                n_obs_min=n_obs_min,
                cache_pcor=cache_pcor,
                time_limit=time_limit,
                update_interval=update_interval,
                parallel_mode=parallel_mode,
                share_data=!no_share_data,
#                experimental_kwargs...
                )

            save_network(output, netw_results)
    catch e
        cmd_error(e.msg)
    end

end

end #module
