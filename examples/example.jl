## Setup
using Pkg
Pkg.activate("examples")
# Pkg.add("JLD2")
# Pkg.add("UnitfulAstro")
# Pkg.add("Unitful")
# Pkg.add(;path="C:/Users/Christian/Dropbox/GP_research/julia/telfitting")
# Pkg.add("Stheno")
# Pkg.add("TemporalGPs")
# Pkg.add("Distributions")
# Pkg.add("Plots")
Pkg.instantiate()

using Plots
include("C:/Users/Christian/Dropbox/GP_research/julia/telfitting/src/telfitting.jl")
tf = Main.telfitting

## Loading (pregenerated) data

include("data_structs.jl")
@load "E:/telfitting/telfitting_workspace_smol.jld2" Spectra airmasses obs_resolution obs_λ planet_P_nu rvs_activ_no_noise rvs_activ_noisy rvs_kep_nu times_nu plot_times plot_rvs_kep
# @load "E:/telfitting/telfitting_workspace.jld2" quiet λ_nu

## Setting up necessary variables and functions

light_speed_nu = 299792458
plot_stuff = true

n_obs = length(Spectra)
len_obs = length(Spectra[1].log_λ_obs)
flux_obs = ones(len_obs, n_obs)
var_obs = zeros(len_obs, n_obs)
log_λ_obs = zeros(len_obs, n_obs)
log_λ_star = zeros(len_obs, n_obs)
for i in 1:n_obs # 13s
    flux_obs[:, i] = Spectra[i].flux_obs
    var_obs[:, i] = Spectra[i].var_obs
    log_λ_obs[:, i] = Spectra[i].log_λ_obs
    log_λ_star[:, i] = Spectra[i].log_λ_bary
end

## Initializing models

star_model_res = 2 * sqrt(2) * obs_resolution
tel_model_res = obs_resolution

@time tf_model = tf.TFModel(log_λ_obs, log_λ_star, star_model_res, tel_model_res)

@time rvs_notel, rvs_naive = tf.initialize!(tf_model, flux_obs)

plot_spectrum(; kwargs...) = plot(; xlabel = "Wavelength (nm)", ylabel = "Continuum Normalized Flux", dpi = 400, kwargs...)
plot_rv(; kwargs...) = plot(; xlabel = "Time (d)", ylabel = "RV (m/s)", dpi = 400, kwargs...)


# plt = plot_rv()
# scatter!(plt, times_nu, rvs_naive)
# scatter!(plt, times_nu, rvs_notel)
# scatter!(plt, times_nu, rvs_activ_no_noise + rvs_kep_nu)


tel_prior() = tf.model_prior(tf_model.tel.lm, [2, 1e3, 1e4, 1e4, 1e7])
star_prior() = tf.model_prior(tf_model.star.lm, [2, 1e-1, 1e3, 1e6, 1e7])

_loss(tel, star, rv, flux_obs, var_obs) =
    sum((((tel .* (star + rv)) - flux_obs) .^ 2) ./ var_obs)
loss_ts(rv, flux_obs, var_obs) = _loss(tf.tel_model(tf_model), tf.star_model(tf_model), rv, flux_obs, var_obs) + tel_prior() + star_prior()
loss_rv(tel, star, flux_obs, var_obs) = _loss(tel, star, tf.rv_model(tf_model), flux_obs, var_obs)

using Flux, Zygote, Optim
# m      = Chain(Dense(1,3,tanh) , Dense(3,1))
# x      = LinRange(-pi,pi,100)'
# y      = sin.(x)
# loss() = mean(abs2, m(x) .- y)
# Zygote.refresh()
# pars   = Flux.params(m)
# lossfun, gradfun, fg!, p0 = tf.optfuns(loss, pars)
# OOptions = Optim.Options(iterations=1000)
# res = Optim.optimize(Optim.only_fg!(fg!), p0, OOptions)
#
#
# plot(m(x)')


OOptions = Optim.Options(iterations=10, f_tol=1e-3, g_tol=1e5)

θ_ts = params(tf_model.star.lm.M, tf_model.star.lm.s, tf_model.star.lm.μ, tf_model.tel.lm.M, tf_model.tel.lm.s, tf_model.tel.lm.μ)
θ_rv = params(tf_model.rv.lm.s)

tf_model.rv.lm.M[:] = tf.calc_doppler_component_RVSKL(tf_model.star.λ, tf_model.star.lm.μ)
lossfun, gradfun, fg!, p0 = tf.optfuns(() -> loss_rv(tf.tel_model(tf_model), tf.star_model(tf_model), flux_obs, var_obs), θ_rv)
res = Optim.optimize(Optim.only_fg!(fg!), p0, OOptions)

s_star_var ./= 5

θ_tot = [M_tel, s_tel, μ_tel, M_star_var, s_star_var, μ_star, s_rv]
θ_tel = [M_tel, s_tel, μ_tel]
θ_star = [M_star_var, s_star_var, μ_star]
θ_rv = [s_rv]

tel_model_result[:, :] = tel_model(θ_tel)
rv_model_result = rv_model(μ_star, θ_rv)
star_model_result = star_model(θ_star)

resid_stds = [std((rvs_notel - rvs_kep_nu) - rvs_activ_no_noise)]
losses = [loss(tel_model_result, star_model_result, rv_model_result)]
tracker = 0

function status_plot(θ_tot; plot_epoch=1)
    tel_model_result = tel_model(view(θ_tot, 1:3))
    star_model_result = star_model(view(θ_tot, 4:6))
    rv_model_result = _rv_model(M_rv, view(θ_tot, 7))

    l = @layout [a; b]
    # predict_plot = plot_spectrum(; legend = :bottomleft, size=(800,1200), layout = l)
    # predict_plot = plot_spectrum(; xlim=(627.8,628.3), legend=:bottomleft, size=(800,1200), layout = l) # o2
    # predict_plot = plot_spectrum(; xlim=(651.5,652), legend=:bottomleft, size=(800,1200), layout = l)  # h2o
    predict_plot = plot_spectrum(; xlim = (647, 656), legend = :bottomleft, size=(800,1200), layout = l)  # h2o
    plot!(predict_plot[1], obs_λ, true_tels[:, plot_epoch], label="true tel")
    plot!(predict_plot[1], obs_λ, flux_obs[:, plot_epoch] ./ (star_model_result[:, plot_epoch] + rv_model_result[:, plot_epoch]), label="predicted tel", alpha = 0.5)
    plot!(predict_plot[1], obs_λ, tel_model_result[:, plot_epoch], label="model tel: $tracker", alpha = 0.5)
    plot_star_λs = exp.(Spectra[plot_epoch].log_λ_star)
    plot!(predict_plot[2], plot_star_λs, flux_obs[:, plot_epoch] ./ true_tels[:, plot_epoch], label="true star", )
    plot!(predict_plot[2], plot_star_λs, flux_obs[:, plot_epoch] ./ tel_model_result[:, plot_epoch], label="predicted star", alpha = 0.5)
    plot!(predict_plot[2], plot_star_λs, star_model_result[:, plot_epoch] + rv_model_result[:, plot_epoch], label="model star: $tracker", alpha = 0.5)
    display(predict_plot)
end
plot_epoch = 60
status_plot(θ_tot; plot_epoch=plot_epoch)

OOptions = Optim.Options(iterations=10, f_tol=1e-3, g_tol=1e5)

println("guess $tracker, std=$(round(std(rvs_notel - rvs_kep_nu - rvs_activ_no_noise), digits=5))")
rvs_notel_opt = copy(rvs_notel)
@time for i in 1:3
    tracker += 1
    println("guess $tracker")

    optimize(f_star, g_star!, θ_holder_to_θ(θ_star, inds_star), LBFGS(), OOptions)
    star_model_result[:, :] = star_model(θ_star)
    M_rv[:, :] = calc_doppler_component_RVSKL(λ_star_template, μ_star)

    optimize(f_tel, g_tel!, θ_holder_to_θ(θ_tel, inds_tel), LBFGS(), OOptions)
    tel_model_result[:, :] = tel_model(θ_tel)

    optimize(f_rv, g_rv!, θ_holder_to_θ(θ_rv, inds_rv), LBFGS(), OOptions)
    rv_model_result[:, :] = rv_model(μ_star, θ_rv)
    rvs_notel_opt[:] = (s_rv .* light_speed_nu)'

    append!(resid_stds, [std(rvs_notel_opt - rvs_kep_nu - rvs_activ_no_noise)])
    append!(losses, [loss(tel_model_result, star_model_result, rv_model_result)])

    println("loss   = $(losses[end])")
    println("rv std = $(round(std((rvs_notel_opt - rvs_kep_nu) - rvs_activ_no_noise), digits=5))")
    status_plot(θ_tot; plot_epoch=plot_epoch)
end

plot(resid_stds; xlabel="iter", ylabel="predicted RV - active RV RMS", legend=false)
plot(losses; xlabel="iter", ylabel="loss", legend=false)

## Plots

if plot_stuff

    # Compare first guess at RVs to true signal
    predict_plot = plot_rv()
    plot!(predict_plot, plot_times .% planet_P_nu, plot_rvs_kep, st=:line, color=:red, lw=1, label="Injected Keplerian")
    plot!(predict_plot, times_nu .% planet_P_nu, rvs_naive, st=:scatter, ms=3, color=:blue, label="Before model")
    png(predict_plot, "figs/model_0_phase.png")

    # Compare RV differences to actual RVs from activity
    predict_plot = plot_rv()
    plot!(predict_plot, times_nu, rvs_activ_noisy, st=:scatter, ms=3, color=:red, label="Activity (with obs. SNR and resolution)")
    plot!(predict_plot, times_nu, rvs_naive - rvs_kep_nu, st=:scatter, ms=3, color=:blue, label="Before model")
    png(predict_plot, "figs/model_0.png")

    # Compare second guess at RVs to true signal
    predict_plot = plot_rv()
    plot!(predict_plot, plot_times .% planet_P_nu, plot_rvs_kep, st=:line, color=:red, lw=1, label="Injected Keplerian")
    plot!(predict_plot, times_nu .% planet_P_nu, rvs_naive, st=:scatter, ms=3, color=:blue, label="Before model")
    plot!(predict_plot, times_nu .% planet_P_nu, rvs_notel, st=:scatter, ms=3, color=:lightgreen, label="Before optimization")
    png(predict_plot, "figs/model_1_phase.png")

    # Compare RV differences to actual RVs from activity
    predict_plot = plot_rv()
    plot!(predict_plot, times_nu, rvs_activ_noisy, st=:scatter, ms=3, color=:red, label="Activity (with obs. SNR and resolution)")
    plot!(predict_plot, times_nu, rvs_notel - rvs_kep_nu, st=:scatter, ms=3, color=:lightgreen, label="Before optimization")
    png(predict_plot, "figs/model_1.png")

    # Compare second guess at RVs to true signal
    predict_plot = plot_rv()
    plot!(predict_plot, plot_times .% planet_P_nu, plot_rvs_kep, st=:line, color=:red, lw=1, label="Injected Keplerian")
    plot!(predict_plot, times_nu .% planet_P_nu, rvs_naive, st=:scatter, ms=3, color=:blue, label="Before model")
    plot!(predict_plot, times_nu .% planet_P_nu, rvs_notel, st=:scatter, ms=3, color=:lightgreen, label="Before optimization")
    plot!(predict_plot, times_nu .% planet_P_nu, rvs_notel_opt, st=:scatter, ms=3, color=:darkgreen, label="After optimization")
    png(predict_plot, "figs/model_2_phase.png")

    # Compare RV differences to actual RVs from activity
    predict_plot = plot_rv()
    plot!(predict_plot, times_nu, rvs_activ_noisy, st=:scatter, ms=3, color=:red, label="Activity (with obs. SNR and resolution)")
    plot!(predict_plot, times_nu, rvs_notel - rvs_kep_nu, st=:scatter, ms=3, color=:lightgreen, label="Before optimization")
    plot!(predict_plot, times_nu, rvs_notel_opt - rvs_kep_nu, st=:scatter, ms=3, color=:darkgreen, label="After optimization")
    png(predict_plot, "figs/model_2.png")

    # predict_plot = plot_spectrum(; xlim=(627.8,628.3)) # o2
    # predict_plot = plot_spectrum(; xlim = (647, 656))  # h2o
    # predict_plot = plot_spectrum(; xlim=(651.5,652))  # h2o
    predict_plot = plot_spectrum(; title="Stellar model")
    plot!(λ_star_template, M_star_var[:,1]; label="basis 1")
    plot!(λ_star_template, M_star_var[:,2]; label="basis 2")
    plot!(λ_star_template, μ_star; label="μ")
    png(predict_plot, "figs/model_star_basis.png")

    predict_plot = plot_spectrum(; xlim=(647, 656), title="Stellar model")  # h2o
    plot!(λ_star_template, M_star_var[:,1]; label="basis 1")
    plot!(λ_star_template, M_star_var[:,2]; label="basis 2")
    plot!(λ_star_template, μ_star; label="μ star")
    plot!(obs_λ, μ_tel; label="μ tel")
    png(predict_plot, "figs/model_star_basis_h2o.png")

    plot_scores(; kwargs...) = plot(; xlabel = "Time (d)", ylabel = "Weights", dpi = 400, kwargs...)
    predict_plot = plot_scores(; title="Stellar model")
    scatter!(times_nu, s_star_var[1, :]; label="weights 1")
    scatter!(times_nu, s_star_var[2, :]; label="weights 2")
    png(predict_plot, "figs/model_star_weights.png")

    predict_plot = plot_spectrum(; title="Telluric model")
    plot!(obs_λ, M_tel[:,1]; label="basis 1")
    plot!(obs_λ, M_tel[:,2]; label="basis 2")
    plot!(obs_λ, μ_tel; label="μ")
    png(predict_plot, "figs/model_tel_basis.png")

    predict_plot = plot_spectrum(;xlim=(647, 656), title="Telluric model (H2O)")  # h2o
    plot!(obs_λ, M_tel[:,1]; label="basis 1")
    plot!(obs_λ, M_tel[:,2]; label="basis 2")
    plot!(obs_λ, μ_tel; label="μ")
    png(predict_plot, "figs/model_tel_basis_h2o.png")
    predict_plot = plot_spectrum(;xlim=(627.8,628.3), title="Telluric model (O2)")  # o2
    plot!(obs_λ, M_tel[:,1]; label="basis 1")
    plot!(obs_λ, M_tel[:,2]; label="basis 2")
    plot!(obs_λ, μ_tel; label="μ")
    png(predict_plot, "figs/model_tel_basis_o2.png")

    predict_plot = plot_scores(; title="Telluric model")
    scatter!(times_nu, s_tel[1, :]; label="weights 1")
    scatter!(times_nu, s_tel[2, :]; label="weights 2")
    scatter!(times_nu, airmasses .- 3; label="airmasses")
    png(predict_plot, "figs/model_tel_weights.png")
end

std((rvs_naive - rvs_kep_nu) - rvs_activ_no_noise)
std((rvs_notel - rvs_kep_nu) - rvs_activ_no_noise)
std((rvs_notel_opt - rvs_kep_nu) - rvs_activ_no_noise)
std((rvs_naive - rvs_kep_nu) - rvs_activ_noisy)
std((rvs_notel - rvs_kep_nu) - rvs_activ_noisy)
std((rvs_notel_opt - rvs_kep_nu) - rvs_activ_noisy)
std(rvs_activ_noisy - rvs_activ_no_noise)  # best case
std(rvs_notel_opt - rvs_kep_nu)
std(rvs_activ_noisy)
std(rvs_activ_no_noise)
