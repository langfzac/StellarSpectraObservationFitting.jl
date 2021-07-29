## Importing packages
using Pkg
using JLD2
Pkg.activate("EXPRES")

# Pkg.develop(;path="C:\\Users\\chris\\OneDrive\\Documents\\GitHub\\EMPCA")
# Pkg.develop(;path="C:\\Users\\chris\\Dropbox\\GP_research\\julia\\StellarSpectraObservationFitting")
# Pkg.add(;url="https://github.com/RvSpectML/RvSpectML.jl")

Pkg.instantiate()

using Statistics
import StellarSpectraObservationFitting; SSOF = StellarSpectraObservationFitting
using Plots

## Setting up necessary variables

stars = ["10700", "26965"]
star = stars[SSOF.parse_args(1, Int, 1)]
interactive = length(ARGS) == 0
save_plots = true
include("data_locs.jl")  # defines expres_data_path and expres_save_path
use_telstar = SSOF.parse_args(2, Bool, true)
desired_order = SSOF.parse_args(3, Int, 68)  # 68 has a bunch of tels, 47 has very few

## Loading in data and initializing model
save_path = expres_save_path * star * "/$(desired_order)/"
@load save_path * "data.jld2" n_obs data times_nu airmasses

if isfile(save_path*"results.jld2")
    @load save_path*"results.jld2" model rvs_naive rvs_notel
    if model.metadata[:todo][:err_estimated]
        @load save_path*"results.jld2" rv_errors
    end
else
    model_res = 2 * sqrt(2) * 150000
    @time model = SSOF.OrderModel(data, model_res, model_res, "EXPRES", desired_order, star; n_comp_tel=20, n_comp_star=20)
    @time rvs_notel, rvs_naive, _, _ = SSOF.initialize!(model, data; use_gp=true)
    model = SSOF.downsize(model, 10, 10)
end

## Creating optimization workspace
if use_telstar
    workspace, loss = SSOF.WorkspaceTelStar(model, data; return_loss_f=true)
else
    workspace, loss = SSOF.WorkspaceTotal(model, data; return_loss_f=true)
end

## Plotting

SSOF_path = dirname(dirname(pathof(SSOF)))
if interactive
    include(SSOF_path * "/src/_plot_functions.jl")
    status_plot(workspace.o, workspace.d)
end

## Improving regularization

if !model.metadata[:todo][:reg_improved]
    @time results_telstar, _ = SSOF.train_OrderModel!(workspace; print_stuff=true, ignore_regularization=true)  # 16s
    @time results_telstar, _ = SSOF.train_OrderModel!(workspace; print_stuff=true, ignore_regularization=true, g_tol=SSOF._g_tol_def/10*sqrt(length(workspace.telstar.p0)), f_tol=1e-8)  # 50s
    using StatsBase
    n_obs_train = Int(round(0.75 * n_obs))
    training_inds = sort(sample(1:n_obs, n_obs_train; replace=false))
    @time SSOF.fit_regularization!(model, data, training_inds; use_telstar=use_telstar)
    model.metadata[:todo][:reg_improved] = true
    model.metadata[:todo][:optimized] = false
    @save save_path*"results.jld2" model rvs_naive rvs_notel
end

## Optimizing model

if !model.metadata[:todo][:optimized]
    @time results_telstar, _ = SSOF.train_OrderModel!(workspace; print_stuff=true)  # 16s
    @time results_telstar, _ = SSOF.train_OrderModel!(workspace; print_stuff=true, g_tol=SSOF._g_tol_def/10*sqrt(length(workspace.telstar.p0)), f_tol=1e-8)  # 50s
    rvs_notel_opt = (model.rv.lm.s .* SSOF.light_speed_nu)'
    if interactive; status_plot(workspace.o, workspace.d) end
    model.metadata[:todo][:optimized] = true
    @save save_path*"results.jld2" model rvs_naive rvs_notel
end

using Distributed
use_distributed = true

if use_distributed
    function sendto(workers::Union{T,Vector{T}}; args...) where {T<:Integer}
        for worker in workers
            for (var_name, var_value) in args
                @spawnat(worker, Core.eval(Main, Expr(:(=), var_name, var_value)))
            end
        end
    end
    addprocs(length(Sys.cpu_info()) - 2)
    # addprocs(1)
    @everywhere using Pkg; @everywhere Pkg.activate("EXPRES"); # @everywhere Pkg.instantiate()
    @everywhere using StellarSpectraObservationFitting; @everywhere SSOF = StellarSpectraObservationFitting
    sendto(workers(), model=model, workspace=workspace)
end

@everywhere function test_ℓ_for_n_comps(n_comps::Vector; return_inters::Bool=false, kwargs...)
    ws, l = SSOF.WorkspaceTelStar(SSOF.downsize(model, n_comps[1], n_comps[2]), workspace.d; return_loss_f=true)
    SSOF.train_OrderModel!(ws; kwargs...)  # 16s
    SSOF.train_OrderModel!(ws; g_tol=SSOF._g_tol_def/10*sqrt(length(ws.telstar.p0)), f_tol=1e-8, kwargs...)  # 50s
    if return_inters
        return ws, l, l()
    else
        return l()
    end
end

test_n_comp_tel = 1:5
test_n_comp_star = 1:5

n_comp_pairs = Vector{Int}[]
for i in test_n_comp_tel
    for j in test_n_comp_star
        append!(n_comp_pairs, [[i,j]])
    end
end
@time comp_ℓs_flat = pmap(x->test_ℓ_for_n_comps(x), n_comp_pairs, batch_size=Int(floor(length(n_comp_pairs) / (nworkers() + 1)) + 1))

n_comps = [10,10]
ws, l = SSOF.WorkspaceTelStar(SSOF.downsize(model, n_comps[1], n_comps[2]), workspace.d; return_loss_f=true)
@time SSOF.train_OrderModel!(ws; show_trace=true)  # 10s
@time SSOF.train_OrderModel!(ws; g_tol=SSOF._g_tol_def/10*sqrt(length(ws.telstar.p0)), f_tol=1e-8, show_trace=true)  # 50s
l()

@time ws, l, _, = test_ℓ_for_n_comps([1,1]; return_inters=true)
status_plot(ws.o, ws.d)


ws.o, ws.d
x = reshape(n_comp_pairs, (3,3))'
x = reshape(comp_ℓs_flat, (3,3))'
x[2,1]
if use_distributed

else
    comp_ℓs = zeros(length(test_n_comp_tel), length(test_n_comp_star))
    for (i, n_tel) in enumerate(test_n_comp_tel)
        for (j, n_star) in enumerate(test_n_comp_star)
            comp_ℓs[i, j] = test_ℓ_for_n_comps([n_tel, n_star])
        end
    end
end

comp_ℓs


holder = pmap(x->kep_unnormalized_posterior_distributed(x), period_grid, batch_size=Int(floor(amount_of_periods / (nworkers() + 1)) + 1))

## Getting RV error bars (only regularization held constant)

if !model.metadata[:todo][:err_estimated]
    data.var[data.var.==Inf] .= 0
    data_noise = sqrt.(data.var)
    data.var[data.var.==0] .= Inf

    data_holder = copy(data)
    model_holder = copy(model)
    n = 50
    rv_holder = zeros(n, length(model.rv.lm.s))
    @time for i in 1:n
        data_holder.flux[:, :] = data.flux + (data_noise .* randn(size(data_holder.var)))
        SSOF.train_OrderModel!(SSOF.WorkspaceTelStar(model_holder, data_holder), g_tol=SSOF._g_tol_def/1*sqrt(length(workspace.telstar.p0)), f_tol=1e-8)
        rv_holder[i, :] = (model_holder.rv.lm.s .* SSOF.light_speed_nu)'
    end
    rv_errors = std(rv_holder; dims=1)
    @save save_path*"results.jld2" model rvs_naive rvs_notel rv_errors
end

## Plots

if save_plots

    include(SSOF_path * "/src/_plot_functions.jl")

    using CSV, DataFrames
    expres_output = CSV.read(SSOF_path * "/EXPRES/" * star * "_activity.csv", DataFrame)
    eo_rv = expres_output."CBC RV [m/s]"
    eo_rv_σ = expres_output."CBC RV Err. [m/s]"
    eo_time = expres_output."Time [MJD]"

    # Compare RV differences to actual RVs from activity
    rvs_notel_opt = (model.rv.lm.s .* SSOF.light_speed_nu)'
    plt = plot_model_rvs_new(times_nu, rvs_notel_opt, rv_errors, eo_time, eo_rv, eo_rv_σ; display_plt=interactive, markerstrokewidth=1)
    png(plt, save_path * "model_rvs.png")

    plt = plot_stellar_model_bases(model; display_plt=interactive)
    png(plt, save_path * "model_star_basis.png")

    plt = plot_stellar_model_scores(model; display_plt=interactive)
    png(plt, save_path * "model_star_weights.png")

    plt = plot_telluric_model_bases(model; display_plt=interactive)
    png(plt, save_path * "model_tel_basis.png")

    plt = plot_telluric_model_scores(model; display_plt=interactive)
    png(plt, save_path * "model_tel_weights.png")

    plt = plot_stellar_model_bases(model; inds=1:4, display_plt=interactive)
    png(plt, save_path * "model_star_basis_few.png")

    plt = plot_stellar_model_scores(model; inds=1:4, display_plt=interactive)
    png(plt, save_path * "model_star_weights_few.png")

    plt = plot_telluric_model_bases(model; inds=1:4, display_plt=interactive)
    png(plt, save_path * "model_tel_basis_few.png")

    plt = plot_telluric_model_scores(model; inds=1:4, display_plt=interactive)
    png(plt, save_path * "model_tel_weights_few.png")

    plt = status_plot(workspace.o, workspace.d; display_plt=interactive)
    png(plt, save_path * "status_plot.png")
end
