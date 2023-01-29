using HypothesisTests
using LinearAlgebra
using Statistics

function moving_average(X, k)
    pad = zeros(eltype(X), k ÷ 2)
    return [pad; [mean(X[i:(i+k)]) for i in 1:(length(X)-k)]; pad]
end

function kmeans(X, num_cluster::Integer; max_iterations=100)
    assignments = ones(typeof(num_cluster), length(X))
    centroids = rand(X, num_cluster)
    converged = (false)
    for iter in 1:max_iterations
        # Assign each data point to its closest cluster
        dists = [norm(a - b) for (a, b) in Iterators.product(X, centroids)]
        new_assignments = [i.I[end] for i in argmin(dists, dims=2)][:]

        # Check if the current assignment is the same as the last one
        if all((a1 == a2) for (a1, a2) in zip(assignments, new_assignments))
            converged = true
            break
        end


        # Update clustering
        centroids .= [mean(X[new_assignments.==i]) for i in 1:num_cluster]
        assignments .= new_assignments
    end
    return (; assignments, converged, centroids)
end
function peak_population2(
    X::AbstractVector;
    smooth=48 * 7 ÷ 2
)
    # Smooth signal
    threshold = mean(X)

    # Whether the previous step is larger than the threshold
    flag::Bool = first(X) >= threshold

    # Peaks
    left = 1
    peaks = Int[]
    sizehint!(peaks, 5)

    # Count the peaks iteratively
    for step in smooth:(lastindex(X)-smooth)
        avg = mean(X[i] for i in step-smooth+1:step+smooth)
        next_flag = avg >= threshold
        if next_flag && !flag
            left = step
        end
        if !next_flag && flag
            peak = argmax((X[i] for i in left:step)) + left
            push!(peaks, peak)
        end
        flag = next_flag
    end

    # The BPH didn't die out at the end, count the last peak
    if flag
        peak = argmax((X[i] for i in left:lastindex(X))) + left
        push!(peaks, peak)
    end

    resize!(peaks, length(peaks))
    return peaks
end

function peak_population(X::AbstractVector;
    smooth=48 * 7 ÷ 2,
    threshold=0.0f0)
    # Smooth signal
    Y = X
    Y = moving_average(X, smooth)
    # Normlize
    Y = (Y .- mean(Y)) ./ std(Y)
    # Find the peaks
    return let r = Y .≥ threshold
        ranges = findall(isone, abs.(diff(r)))
        if isodd(length(ranges))
            push!(range, length(X))
        end
        map(Iterators.partition(ranges, 2)) do (a, b)
            _, offset = findmax(@view X[a:b])
            return a + offset
        end
    end
end

function batch_peak_populations(populations; strict::Bool=false, kwargs...)
    peakss = map(peak_population2, populations)
    num_peaks = map(length, peakss)

    # Remove anomalies
    peaks = let μ = mean(num_peaks),
        σ = std(num_peaks)

        [
            peaks for (num_peak, peaks) in zip(num_peaks, peakss)
            if μ - 3σ <= num_peak <= μ + 3σ
        ]
    end

    # Binning to match the peaks
    num_cluster = maximum(num_peaks)
    flatten_peaks = convert.(Float32, Iterators.flatten(peakss))
    kmeans_result = kmeans(flatten_peaks, num_cluster)
    if strict
        @assert kmeans_result.converged
    end

    # Find the peaks according to batch results
    peaks = [
        mean(flatten_peaks[kmeans_result.assignments.==i])
        for i in 1:num_cluster
    ]
    return peaks
end


function test_effectiveness(foods::AbstractMatrix, p0; alpha=0.05)
    # foods: [time, experiment]
    # p0: chances that the crop will suffer from the BPH (risk probablity)
    # alpha: pvalue threshold

    # 100 allows a bit of deviation, incase the result is really really close
    goods = @views foods[end, :] .≥ (foods[begin, :] * 0.5 .- 100)
    _, total = size(foods)
    num_goods = count(goods)

    # Perform a left tail testing
    # H0: flower is effective: good / total ≥ p0
    # H1: flower is not effective: good / total < p0
    # Effective means accept H0, which means pvalue < alpha
    # H1 is p < p0, which means the tail is on the left
    test = BinomialTest(num_goods, total, p0)

    # pvalue function only calculates then tail's value
    pv = pvalue(test; tail=:left)
    effective = alpha < pv
    return (; pvalue=pv, total=total, num_goods=num_goods, effective=effective, goods=goods)
end

"""
    test_effectiveness(foods; alpha=0.05)

Returns (; test, pass, pvalue) where `test` is a OneSampleTTest,
`pass` is a Bool indicate whether we accept that the flow is effective or not.

The criteria is whether the amount of protected rice is at least `0.5`.
"""
function test_effectiveness(foods::AbstractMatrix; alpha=0.05)
    # foods: [time, experiment]
    # p0: chances that the crop will suffer from the BPH (risk probablity)
    # alpha: pvalue threshold

    # Food retain ratio
    food_ratios = foods[end, :] ./ foods[begin, :]

    # Perform T-Test
    # r: food retain ratio
    # H0: r = 0.5
    # H1: r > 0.5
    # Good == reject H0 == pvalue < alpha
    test = OneSampleTTest(food_ratios, 0.5)
    pvalue = HypothesisTests.pvalue(test, tail=:right)
    pass = pvalue < alpha

    # The result shown in the test repr is for BOTH size test
    # Don't trust those
    return (; test, pass, pvalue)
end
