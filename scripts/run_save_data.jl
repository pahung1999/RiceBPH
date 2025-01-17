using Distributed
@everywhere begin
    using Pkg
    Pkg.activate(joinpath(@__DIR__, ".."))
end

# The real work

@everywhere begin
    using SharedArrays
    using Comonicon
    using RiceBPH
    using JLD2
    using ProgressMeter
    using DataFrames
end

const BASEPATH = joinpath(@__DIR__, "..")
const MAPSPATH = joinpath(BASEPATH, "assets", "envmaps")

const experiments = let
    # First parameters set
    p1 = Dict{Symbol,Vector}()
    maps = ["012-1x2.csv",
            "013-1x2.csv",
            "014-1x2.csv",
            "015-1x2.csv",
            "016-1x2.csv",
            "017-1x2.csv",
            "018-1x2.csv",
            "019-1x2.csv",
            "020-1x2.csv",
            "12-3x3.csv",
            "13-3x3.csv",
            "14-3x3.csv",
            "15-3x3.csv",
            "16-3x3.csv",
            "17-3x3.csv",
            "18-3x3.csv",
            "19-3x3.csv",
            "20-3x3.csv"]
    p1[:envmap] = joinpath.(MAPSPATH, maps)
    p1[:init_position] = [:corner, :border]
    p1[:init_nb_bph] = [200, 20]
    p1[:init_pr_eliminate] = Float32[0.075, 0.09, 0.12, 0.15]
    e1 = RiceBPH.create_experiments(; p1...)

    # Second parameter set
    p2 = Dict{Symbol,Vector}()
    p2[:init_position] = [:border, :corner]
    p2[:init_nb_bph] = [20, 200]
    p2[:init_pr_eliminate] = Float32[0.15]
    p2[:envmap] = [joinpath(MAPSPATH, "no-flower.csv")]
    e2 = RiceBPH.create_experiments(; p2...)

    # Third parameter set
    p3 = Dict{Symbol,Vector}()
    p3[:init_nb_bph] = [20, 200]
    p3[:init_position] = [:border, :corner]
    p3[:init_pr_eliminate] = Float32[0.0f0]
    p3[:envmap] = joinpath.(MAPSPATH, ["019-1x2.csv", "19-3x3.csv"])
    e3 = RiceBPH.create_experiments(; p3...)

    # Concat
    #= @info length(e1) =#
    #= @info length(e2) =#
    #= @info length(e3) =#
    Set([e1; e2; e3])
end

@info "Number of scenarios: $(length(experiments))"

function run_save_result!(output_file, params, num_replicate::Int)
    results = @showprogress pmap(1:num_replicate) do seed
        return RiceBPH.run_simulation(params; seed=seed)
    end
    io = jldopen(output_file, "w")
    io["params"] = params
    io["results"] = results
    return close(io)
end

@main function main(; output_dir::String,
                    num_procs::Int=1,
                    num_replicate::Int=1000)
    if num_procs > 1
        addprocs(num_procs - 1)
    end
    mkpath(output_dir)
    for (name, params) in experiments
        @info "Running: $name"
        output_file = joinpath(output_dir, "$(name).jld2")
        run_save_result!(output_file, params, num_replicate)
    end
end
