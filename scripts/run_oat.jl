const BASEDIR = joinpath(@__DIR__, "..")
const MAPSDIR = joinpath(BASEDIR, "assets", "envmaps")

using Pkg
Pkg.activate(BASEDIR)
using Base.Iterators
using RiceBPH.Model
using RiceBPH
using Comonicon
using TOML
using ProgressMeter
using Chain
using DataFrames

function julia_main(oat_config, num_replications)
    parameter_sets = Dict()
    for (k_, v) in oat_config["params"]
        k = Symbol(k_)
        if v isa Dict
            kwargs = (Symbol(prop) => v[prop] for prop in keys(v))
            parameter_sets[k] = range(; kwargs...)
        elseif v isa AbstractVector
            parameter_sets[k] = v
        else
            parameter_sets[k] = [v]
        end
    end
    parameters = @chain begin
        ([k => v for v in vs] for (k, vs) in parameter_sets)
        Iterators.product(_...)
        Iterators.map(Dict, _)
    end
    num_simulations = num_replications * length(parameters)
    @info "Total number of simulations: $(num_simulations)"
    pbar = Progress(num_simulations; desc="Running similation")
    rows = NamedTuple[]
    for parameter in parameters
        results = DataFrame[]
        sizehint!(results, num_replications)
        for rep in 1:num_replications
            result = RiceBPH.Model.run_simulation(; seed=rep, parameter...)
            next!(pbar)
            push!(results, result)
        end
        rices = [r.num_healthy_rice for r in results]
        populations = [r.count_is_alive for r in results]
        row = merge(
            NamedTuple(parameter),
            RiceBPH.replication_statistics(;
                populations=populations,
                rices=rices
            )
        )
        push!(rows, row)
    end

    rows_d = [
        Dict(string(k) => getproperty(d, k) for k in propertynames(d))
        for d in rows
    ]
    return Dict("outputs" => rows_d)
end

@main function main(oat_config; num_replications::Int=50)
    oat_config_files = if isfile(oat_config)
        [oat_config]
    elseif isdir(oat_config)
        joinpath.(oat_config, readdir(oat_config))
    end
    outputdir = "oat_outputs"
    mkpath(outputdir)
    for oat_config_file in oat_config_files
        config = TOML.parse(read(oat_config_file, String))
        output_file = joinpath(outputdir, basename(oat_config_file))
        @info "Processing $oat_config_file"
        outputs = julia_main(config, num_replications)
        open(output_file, "w") do io
            TOML.print(io, outputs)
        end
    end
end
