## Setup
using Pkg
Pkg.activate("EXPRES")
Pkg.instantiate()

## Importing data with Eric's code

stars = ["10700", "26965"]
star = stars[2]

import StellarSpectraObservationFitting; SSOF = StellarSpectraObservationFitting
using RvSpectMLBase, RvSpectML
using EchelleInstruments, EchelleInstruments.EXPRES
using CSV, DataFrames, Query, StatsBase, Statistics, Dates
using JLD2

target_subdir = star * "/"   # USER: Replace with directory of your choice
fits_target_str = star
paths_to_search_for_param = ["EXPRES"]

expres_data_path = "E:/telfitting/"
expres_save_path = "E:/telfitting/"

if !isfile(init_jld2)
	# NOTE: make_manifest does not update its paths_to_search when default_paths_to_search is defined here, so if you change the line above, you must also include "paths_to_search=default_paths_to_search" in the make_manifest() function call below
init_jld2 = expres_save_path * target_subdir * "init.jld2"
	pipeline_plan = PipelinePlan()
	dont_make_plot!(pipeline_plan, :movie)
	reset_all_needs!(pipeline_plan)
	masks = Array{UnitRange, 2}(undef, length(readdir(expres_data_path * target_subdir)), 86)

	if need_to(pipeline_plan,:read_spectra)
	    df_files = make_manifest(expres_data_path, target_subdir, EXPRES)
	    # Reading in customized parameters from param.jl.
	    eval(code_to_include_param_jl(paths_to_search=paths_to_search_for_param))
	    # Reading in FITS files
	    all_spectra = Spectra2DExtended[]
	    for j in 1:size(masks, 1)
	        row = eachrow(df_files_use)[j]
	        spectra, mask = EXPRES.read_data(row; store_min_data=true, store_tellurics=true, normalization=:blaze, return_λ_obs=true, return_excalibur_mask=true)
	        append!(all_spectra, [spectra])
	        for i in 1:size(mask, 2)
	            try
	                x = findfirst(view(mask, :, i)):findlast(view(mask, :, i))
	                masks[j, i] = x
	                @assert all(mask[x, i] .== true)
	            catch y
	                if typeof(y)==MethodError
	                    masks[j, i] = 0:0
	                else
	                    throw(y)
	                end
	            end
	        end
	    end
	    GC.gc()
	    dont_need_to!(pipeline_plan,:read_spectra)
	end

	inds = Vector{UnitRange}(undef, size(masks,2))
	for i in 1:length(inds)
	    inds[i] = maximum([mask[1] for mask in masks[:, i]]):minimum([mask[end] for mask in masks[:, i]])
	end
	# Something buggy if include order 1.  Order 86 essentially ignored due to tellurics. First and last orders have NaN issues
	#max_orders = 12:83
	lfc_orders = 43:72
	order_list_timeseries = extract_orders(all_spectra, pipeline_plan; orders_to_use=lfc_orders, recalc=true)

	times_nu = pipeline_plan.cache[:extract_orders].times
	airmasses = [parse(Float64, md[:airmass]) for md in pipeline_plan.cache[:extract_orders].metadata]

	@save init_jld2 times_nu airmasses order_list_timeseries lfc_orders inds masks all_spectra pipeline_plan
else
	@load init_jld2 times_nu airmasses order_list_timeseries lfc_orders inds masks all_spectra pipeline_plan
end

## Switching to my data format

n_obs = length(all_spectra)
obs_resolution = 150000
desired_order = 68  # 68 has a bunch of tels, 47 has very few
mask_inds = inds[desired_order]
# inst = all_spectra[1].inst
# extra_chop = 0
# mask_inds = (min_col_default(inst, desired_order) + extra_chop):(max_col_default(inst, desired_order) - extra_chop)  # 850:6570
# mask_inds = 2270:5150

# using Plots
# plot(all_spectra[1].metadata[:tellurics][:, desired_order])

len_obs = length(mask_inds)
flux_obs = ones(len_obs, n_obs)
var_obs = zeros(len_obs, n_obs)
log_λ_obs = zeros(len_obs, n_obs)
log_λ_star = zeros(len_obs, n_obs)
for i in 1:n_obs # 13s
    flux_obs[:, i] = all_spectra[i].flux[mask_inds, desired_order]
    var_obs[:, i] = all_spectra[i].var[mask_inds, desired_order]
    log_λ_obs[:, i] = log.(all_spectra[i].λ_obs[mask_inds, desired_order])
    log_λ_star[:, i] = log.(all_spectra[i].λ[mask_inds, desired_order])
end
tf_data = SSOF.TFData(flux_obs, var_obs, log_λ_obs, log_λ_star)
# i=10
# SSOF.fit_continuum(tf_data.log_λ_obs[:, i], tf_data.flux[:, i], tf_data.var[:, i]; order=6, plot_stuff=true)

@time SSOF.process!(tf_data; order=6)

# using Plots
#
# snr = sqrt.(tf_data.flux.^2 ./ tf_data.var)
# heatmap(snr)
# histogram(collect(Iterators.flatten(snr)))
#
# plt = plot(;xlabel="MJD", ylabel="Å", title="EXPRES wavelength calibration ($star, order $desired_order)")
# for i in 1:10
#     scatter!(plt, times_nu, exp.(log_λ_obs[i, :]); label="pixel $(mask_inds[i])")
# end
# display(plt)
# png("obs.png")
#
# plt = plot(;xlabel="MJD", ylabel="Å", title="EXPRES wavelength calibration ($star, order $desired_order)")
# for i in 1:10
#     scatter!(plt, times_nu, exp.(log_λ_star[i, :]); label="pixel $(mask_inds[i])")
# end
# display(plt)
# png("bary.png")

## Initializing models

star_model_res = 2 * sqrt(2) * obs_resolution
tel_model_res = 2 * sqrt(2) * obs_resolution

@time tf_model = SSOF.TFOrderModel(tf_data, star_model_res, tel_model_res, "EXPRES", desired_order, star; n_comp_tel=20, n_comp_star=20)
@time rvs_notel, rvs_naive, fracvar_tel, fracvar_star = SSOF.initialize!(tf_model, tf_data; use_gp=true)


@save expres_save_path * star * "/$(desired_order).jld2" tf_model n_obs tf_data rvs_naive rvs_notel times_nu airmasses

include("../src/_plot_functions.jl")
plot_stellar_model_bases(tf_model; inds=1:10)
plot_stellar_model_scores(tf_model; inds=1:10)
plot_telluric_model_bases(tf_model; inds=1:10)
plot_telluric_model_scores(tf_model; inds=1:10)

function proposed_new_cuts(M::AbstractVector, mask_inds::UnitRange)
    abs_M = abs.(M)
    # plot((1:length(abs_M)) ./ length(abs_M), sort(abs_M); xrange=(0.9,1))
    # cdf = [sum(view(abs_M, 1:i)) for i in 1:length(abs_M)] ./ sum(abs_M)
    # plot(cdf)
    high_M = quantile(abs_M, 0.99)
    half = Int(floor(length(abs_M) / 2))
    cuts = [1, length(abs_M)]
    cut_low = findlast((x) -> x > high_M, abs_M[1:half])
    cut_high = findfirst((x) -> x > high_M, abs_M[(half+1):end])
    if cut_low!=nothing; cuts[1] = cut_low + 1 end
    if cut_high!=nothing; cuts[2] = half + cut_high - 1 end
    return cuts
end
function proposed_new_inds(cuts::Vector, M::AbstractVector, mask_inds::UnitRange)
    # println(maximum(abs_M) / high_M)
    cuts2 = Int.(round.(length(mask_inds) .* (cuts ./ length(M))))
    return (mask_inds[1] + cuts2[1]):(mask_inds[1] + cuts2[2])
end
function new_inds(M::AbstractArray, mask_inds::UnitRange)
    possible_new_inds_tfm = [proposed_new_cuts(M[:, i], mask_inds) for i in 1:size(M, 2)]
    possible_new_inds_mask = [proposed_new_inds(possible_new_inds_tfm[i], M[:, i], mask_inds) for i in 1:size(M, 2)]
    return [maximum([inds[1] for inds in possible_new_inds_mask]), minimum([inds[end] for inds in possible_new_inds_mask])],
        [maximum([inds[1] for inds in possible_new_inds_tfm]), minimum([inds[end] for inds in possible_new_inds_tfm])]
end
_, tfm_inds = new_inds(tf_model.star.lm.M, mask_inds)
tf_model.star.lm.M[1:tfm_inds[1], :] .= 0
tf_model.star.lm.M[tfm_inds[2]:end, :] .= 0
_, tfm_inds = new_inds(tf_model.tel.lm.M, mask_inds)
tf_model.tel.lm.M[1:tfm_inds[1], :] .= 0
tf_model.tel.lm.M[tfm_inds[2]:end, :] .= 0

plot_stellar_model_bases(tf_model)
plot_telluric_model_bases(tf_model)

##  Continuum GIF, do before SSOF.process!
function fit_continuum_gif(x::AbstractVector, y::AbstractVector, σ²::AbstractVector; order::Int=6, nsigma::Vector{<:Real}=[0.3,3.0], maxniter::Int=50, filename::String="show_continuum_fit.gif")
    A = StellarSpectraObservationFitting.vander(x .- mean(x), order)
    m = fill(true, length(x))
    μ = ones(length(x))
	ex = exp.(x)
    anim = @animate for i in 1:maxniter
        m[σ² .== Inf] .= false  # mask out the bad pixels
        w = StellarSpectraObservationFitting.general_lst_sq(view(A, m, :), view(y, m), view(σ², m))
        μ[:] = A * w
		plt = plot_spectrum(; ylabel = "Blaze Normalized Flux")
		my_scatter!(plt, ex[m], y[m]; label="")
		my_scatter!(plt, ex[.!m], y[.!m]; label="")
		plot!(plt, ex, μ; label="")
        resid = y - μ
        # sigma = median(abs.(resid))
		sigma = std(resid)
        m_new = (-nsigma[1]*sigma) .< resid .< (nsigma[2]*sigma)
        if sum(m) == sum(m_new); break end
        m = m_new
    end
	gif(anim, filename, fps = 3)
    return μ
end

include("../src/_plot_functions.jl")
i=10
fit_continuum_gif(tf_data.log_λ_obs[:, i], tf_data.flux[:, i], tf_data.var[:, i]; order=6)

## Wavelength calibration plot
plt = _my_plot(;xlabel="MJD", ylabel="Observer Frame Wavelength (Å)", title="Wavelength Calibration", thickness_scaling=3)
for i in 1:5
    scatter!(plt, times_nu, exp.(log_λ_obs[i, :]); label="Pixel $(mask_inds[i])", markerstrokewidth=0)
end
display(plt)
png("obs.png")

plt = _my_plot(;xlabel="MJD", ylabel="Barycentric Frame Wavelength (Å)", title="Wavelength Calibration", thickness_scaling=3, markerstrokestyle=:dash)
for i in 1:5
    scatter!(plt, times_nu, exp.(log_λ_star[i, :]); label="Pixel $(mask_inds[i])", markerstrokewidth=0)
end
display(plt)
png("bary.png")
