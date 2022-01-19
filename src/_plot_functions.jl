using LinearAlgebra
using Plots
using Statistics

_plt_dpi = 400
_plt_size = (1920,1080)
_thickness_scaling = 2
# _theme = :default
_theme = :juno
_my_plot(; dpi = _plt_dpi, size = _plt_size, thickness_scaling=_thickness_scaling, kwargs...) =
    plot(; dpi=dpi, size=size, thickness_scaling=thickness_scaling, kwargs...)
function my_plot(x, y; kwargs...)
    plt = _my_plot(; kwargs...)
    plot!(plt, x, y; kwargs...)
end
plot_spectrum(; xlabel = "Wavelength (Å)", ylabel = "Continuum Normalized Flux + Const", kwargs...) =
    _my_plot(; xlabel=xlabel, ylabel=ylabel, kwargs...)
plot_rv(; xlabel = "Time (d)", ylabel = "RV (m/s)", kwargs...) =
    _my_plot(; xlabel=xlabel, ylabel=ylabel, kwargs...)
plot_scores(; xlabel = "Time (d)", ylabel = "Weights + Const", kwargs...) =
    _my_plot(; xlabel=xlabel, ylabel=ylabel, kwargs...)
theme(_theme)
function my_scatter(x::AbstractVecOrMat, y::AbstractVecOrMat; kwargs...)
    plt = _my_plot(; kwargs...)
    scatter!(plt, x, y; kwargs...)
end
my_scatter!(plt::Union{Plots.AbstractPlot,Plots.AbstractLayout}, x::AbstractVecOrMat, y::AbstractVecOrMat; markerstrokewidth::Real=0, kwargs...) = scatter!(plt, x, y; markerstrokewidth=markerstrokewidth, kwargs...)
_theme == :default ? plt_colors = palette(_theme).colors.colors : plt_colors = PlotThemes._themes[_theme].defaults[:palette].colors.colors
function plot_model_rvs(times_nu::AbstractVector{T}, rvs_naive::AbstractVector{T}, rvs_notel::AbstractVecOrMat{T}, rvs_notel_opt::AbstractVecOrMat{T}, inst_times::AbstractVector{T}, inst_rvs::AbstractVector{T}, inst_rvs_σ::AbstractVector{T}; display_plt::Bool=true) where {T<:Real}
    plt = plot_rv()
    my_scatter!(plt, times_nu, rvs_naive, label="Naive, std: $(round(std(rvs_naive), digits=3))", alpha = 0.2)
    my_scatter!(plt, times_nu, rvs_notel, label="Before optimization, std: $(round(std(rvs_notel), digits=3))", alpha = 0.2)
    my_scatter!(plt, inst_time, inst_rvs; yerror=inst_rvs_σ, label="Instrument RVs, std: $(round(std(inst_rvs), digits=3))")
    my_scatter!(plt, times_nu, rvs_notel_opt, label="After optimization, std: $(round(std(rvs_notel_opt), digits=3))", alpha = 0.7)
    if display_plt; display(plt) end
    return plt
end
intra_night_std(rvs, times) = median([std(rvs[i]) for i in SSOF.observation_night_inds(times) if length(i)>3])
function plot_model_rvs_new(times_nu::AbstractVector{T}, model_rvs::AbstractVecOrMat{T}, model_rvs_σ::AbstractVecOrMat{T}, inst_times::AbstractVector{T}, inst_rvs::AbstractVector{T}, inst_rvs_σ::AbstractVector{T}; display_plt::Bool=true, kwargs...) where {T<:Real}
    plt = plot_rv(; legend=:bottomleft, layout=grid(2, 1, heights=[0.7, 0.3]))
    ervs = inst_rvs .- median(inst_rvs)
    mrvs = model_rvs .- median(model_rvs)
    my_scatter!(plt[1], inst_times, ervs; yerror=inst_rvs_σ, label="Instrument RVs, std: $(round(std(inst_rvs), digits=3)), intra night std: $(round(intra_night_std(inst_rvs, inst_times), digits=3))", xlabel="", kwargs...)
    my_scatter!(plt[1], times_nu, mrvs; yerror=model_rvs_σ, label="Model RVs,    std: $(round(std(model_rvs), digits=3)), intra night std: $(round(intra_night_std(model_rvs, inst_times), digits=3))", alpha = 0.7, kwargs...)
    resids = mrvs - ervs
    my_scatter!(plt[2], times_nu, resids, ylabel="model - Instrument (m/s)", yerror=sqrt.(model_rvs_σ .^ 2 + inst_rvs_σ .^ 2), alpha = 0.5, label="std: $(round(std(resids), digits=3))", markerstrokewidth=1)
    if display_plt; display(plt) end
    return plt
end
function plot_model_rvs_new(times_nu::AbstractVector{T}, model_rvs::AbstractVecOrMat{T}, model_rvs_σ::AbstractVecOrMat{T}, inst_times::AbstractVector{T}, inst_rvs::AbstractVector{T}, inst_rvs_σ::AbstractVector{T}, ccf_rvs::AbstractVector{T}; display_plt::Bool=true, kwargs...) where {T<:Real}
    plt = plot_model_rvs_new(times_nu, model_rvs, model_rvs_σ, inst_times, inst_rvs, inst_rvs_σ; markerstrokewidth=1)
    my_scatter!(plt[1], inst_times, ccf_rvs .- median(ccf_rvs); label="CCF RVs,      std: $(round(std(ccf_rvs), digits=3)), intra night std: $(round(intra_night_std(ccf_rvs, inst_times), digits=3))", alpha = 0.7, kwargs...)
    if display_plt; display(plt) end
    return plt
end

function plot_stellar_model_bases(om::StellarSpectraObservationFitting.OrderModel; inds::UnitRange=1:size(om.star.lm.M, 2), display_plt::Bool=true, kwargs...)
    plt = plot_spectrum(; title="Stellar Model Bases", legend=:outerright, kwargs...)
    plot!(om.tel.λ, om.tel.lm.μ; label="μₜₑₗ", alpha=0.3, color=:white)
    plot!(om.star.λ, om.star.lm.μ; label="μₛₜₐᵣ")
    shift = 0.2
    for i in reverse(inds)
        c_ind = ((i - inds[1] + 3) % 19) + 1
        plot!(om.star.λ, (om.star.lm.M[:, i] ./ norm(om.star.lm.M[:, i])) .- shift * (i - 1); label="Basis $i", color=plt_colors[c_ind])
    end
    if display_plt; display(plt) end
    return plt
end
function plot_stellar_model_scores(om::StellarSpectraObservationFitting.OrderModel; inds::UnitRange=1:size(om.star.lm.M, 2), display_plt::Bool=true, kwargs...)
    plt = plot_scores(; title="Stellar Model Weights", legend=:outerright, kwargs...)
    shift = ceil(10 * maximum([std(om.star.lm.s[inds[i], :] .* norm(om.star.lm.M[:, inds[i]])) for i in inds])) / 2
    for i in reverse(inds)
        c_ind = ((i - inds[1] + 3) % 19) + 1
        my_scatter!(plt, times_nu, (om.star.lm.s[i, :] .* norm(om.star.lm.M[:, i])) .- shift * (i - 1); label="Weights $i", color=plt_colors[c_ind])
        hline!([-shift * (i - 1)]; label="", color=plt_colors[c_ind], lw=3, alpha=0.4)
    end
    if display_plt; display(plt) end
    return plt
end

function plot_telluric_model_bases(om::StellarSpectraObservationFitting.OrderModel; inds::UnitRange=1:size(om.tel.lm.M, 2), display_plt::Bool=true, kwargs...)
    plt = plot_spectrum(; title="Telluric Model Bases", legend=:outerright, kwargs...)
    plot!(om.star.λ, om.star.lm.μ; label="μₛₜₐᵣ", alpha=0.3, color=:white)
    plot!(om.tel.λ, om.tel.lm.μ; label="μₜₑₗ")
    shift = 0.2
    for i in reverse(inds)
        c_ind = ((i - inds[1] + 3) % 19) + 1
        plot!(om.tel.λ, (om.tel.lm.M[:, i] ./ norm(om.tel.lm.M[:, i])) .- shift * (i - 1); label="Basis $i", color=plt_colors[c_ind])
    end
    if display_plt; display(plt) end
    return plt
end
function plot_telluric_model_scores(om::StellarSpectraObservationFitting.OrderModel; inds::UnitRange=1:size(om.tel.lm.M, 2), display_plt::Bool=true, kwargs...)
    plt = plot_scores(; title="Telluric Model Weights", legend=:outerright, kwargs...)
    my_scatter!(plt, times_nu, airmasses; label="Airmasses")
    hline!([1]; label="", color=plt_colors[1], lw=3, alpha=0.4)
    shift = ceil(10 * maximum([std(om.tel.lm.s[inds[i], :] .* norm(om.tel.lm.M[:, inds[i]])) for i in inds])) / 2
    half_shift = ceil(shift) / 2
    for i in reverse(inds)
        c_ind = ((i - inds[1] + 3) % 19) + 1
        my_scatter!(plt, times_nu, (om.tel.lm.s[i, :] .* norm(om.tel.lm.M[:, i])) .- (shift * (i - 1) + half_shift); label="Weights $i", color=plt_colors[c_ind])
        hline!([-(shift * (i - 1) + half_shift)]; label="", color=plt_colors[c_ind], lw=3, alpha=0.4)
    end
    if display_plt; display(plt) end
    return plt
end

function status_plot(o::StellarSpectraObservationFitting.Output, d::StellarSpectraObservationFitting.Data; plot_epoch::Int=10, tracker::Int=0, display_plt::Bool=true, kwargs...)
    obs_mask = .!(isinf.(d.var[:, plot_epoch]))
    obs_λ = exp.(d.log_λ_obs[:, plot_epoch])
    plot_star_λs = exp.(d.log_λ_star[:, plot_epoch])
    plt = plot_spectrum(; legend = :bottomright, layout = grid(2, 1, heights=[0.85, 0.15]), kwargs...)

    plot!(plt[1], obs_λ, o.tel[:, plot_epoch], label="Telluric Model")

    shift = 1.1 - minimum(o.tel[:, plot_epoch])
    star_model = o.star[:, plot_epoch] + o.rv[:, plot_epoch]
    plot!(plt[1], obs_λ, star_model .- shift, label="Stellar Model")

    shift += 1.1 - minimum(star_model)
    my_scatter!(plt[1], obs_λ[obs_mask], d.flux[obs_mask, plot_epoch] .- shift, label="Observed Data", color=:white, alpha=0.1, xlabel="")
    plot!(plt[1], obs_λ, o.total[:, plot_epoch] .- shift, label="Full Model", ls=:dash, color=:white)
    # plot!(plt[1], obs_λ, o.tel[:, plot_epoch] .* star_model .- shift, label="Full Model", ls=:dash, color=:white)

    my_scatter!(plt[2], obs_λ[obs_mask], d.flux[obs_mask, plot_epoch] - o.total[obs_mask, plot_epoch], ylabel="Residuals", label="", alpha=0.1, color=:white)
    # my_scatter!(plt[2], obs_λ, d.flux[:, plot_epoch] - (o.tel[:, plot_epoch] .* star_model), ylabel="Residuals", label="", alpha=0.1, color=:white)
    if display_plt; display(plt) end
    return plt
end
status_plot(mws::StellarSpectraObservationFitting.ModelWorkspace; kwargs...) =
    status_plot(mws.o, mws.d; kwargs...)

function component_test_plot(ys::Matrix, test_n_comp_tel::AbstractVector, test_n_comp_star::AbstractVector; size=(_plt_size[1],_plt_size[2]*1.5), ylabel="ℓ")
    plt = _my_plot(; ylabel=ylabel, layout=grid(2, 1), size=size)
    for i in eachindex(test_n_comp_tel)
        plot!(plt[1], test_n_comp_star, ys[i, :]; label="$(test_n_comp_tel[i]) tel", xlabel="# of stellar components")
    end
    for i in eachindex(test_n_comp_star)
        plot!(plt[2], test_n_comp_tel, ys[:, i]; label="$(test_n_comp_star[i]) stellar", xlabel="# of telluric components")
    end
    display(plt)
    return plt
end
