## Importing packages
using Pkg
Pkg.activate("NEID")
Pkg.instantiate()

using JLD2
import StellarSpectraObservationFitting; SSOF = StellarSpectraObservationFitting
using CSV, DataFrames

## Setting up necessary variables

SSOF_path = dirname(dirname(pathof(SSOF)))
include(SSOF_path * "/src/_plot_functions.jl")
stars = ["10700"]
orders2inds(selected_orders::AbstractVector) = [searchsortedfirst(orders, order) for order in selected_orders]
# prep_str = "noreg_"
prep_str = ""

# for star_ind in 1:2
star_ind = SSOF.parse_args(1, Int, 1)
orders_list = [4:122]
star = stars[star_ind]
orders = orders_list[star_ind]

## Looking at model components

@load "neid_$(prep_str)$(star)_md.jld2" n_comps n_comps_bic robust

n_robust = .!robust
x = orders_list[star_ind]
annot=text.(x, :top, :white, 5)
α = 1
# robust_str = ["" for i in x]
# for i in eachindex(robust_str)
#     robust_str[i] *= "$(x[i])"
#     if !robust[i]; robust_str[i] *= "!" end
# end
# annot=text.(robust_str, :top, :white, 9)
plt = _my_plot(; ylabel="# of basis vectors", xlabel="Order", title="Best Models for $star (Based on AIC)", xticks=false)
my_scatter!(plt, x, n_comps[:, 1]; alpha=α, label="# of telluric components", legend=:top, series_annotations=annot)
my_scatter!(plt, x, n_comps[:, 2]; alpha=α, label="# of stellar components", series_annotations=annot)
plot!(plt, x, n_comps[:, 1]; label = "", alpha=α, color=plt_colors[1], ls=:dot)
plot!(plt, x, n_comps[:, 2]; label = "", alpha=α, color=plt_colors[2], ls=:dot)
my_scatter!(plt, x[n_robust], n_comps_bic[n_robust, 1]; alpha=α/2, color=plt_colors[11], label="# of telluric components (BIC)")
my_scatter!(plt, x[n_robust], n_comps_bic[n_robust, 2]; alpha=α/2, color=plt_colors[12], label="# of stellar components (BIC)")
plot!(plt, x, n_comps_bic[:, 1]; label = "", alpha=α/2, color=plt_colors[11], ls=:dot)
plot!(plt, x, n_comps_bic[:, 2]; label = "", alpha=α/2, color=plt_colors[12], ls=:dot)

png(plt, "neid_$(prep_str)md_$star.png")

## RV reduction

@load "neid_$(prep_str)$(star)_rvs.jld2" rvs rvs_σ n_obs times_nu airmasses n_ord
# # plotting order means which don't matter because the are constant shifts for the reduced rv
# my_scatter(orders, mean(rvs; dims=2); series_annotations=annot, legend=:topleft)
rvs .-= median(rvs; dims=2)
med_rvs_σ = vec(median(rvs_σ; dims=2))
rvs_std = vec(std(rvs; dims=2))
σ_floor = 50

annot = text.(orders[rvs_std .< σ_floor], :center, :black, 3)
plt = my_scatter(orders[rvs_std .< σ_floor], rvs_std[rvs_std .< σ_floor]; legend=:topleft, label="", title="$star RV std", xlabel="Order", ylabel="m/s", size=(_plt_size[1]*0.5,_plt_size[2]*0.75), series_annotations=annot, ylim=[0,σ_floor])
annot = text.(orders[rvs_std .> σ_floor], :center, :black, 3)
my_scatter!(plt, orders[rvs_std .> σ_floor], ones(sum(rvs_std .> σ_floor)) .* σ_floor; label="", series_annotations=annot, markershape=:utriangle, c=plt_colors[1])
png(plt, "neid_" * prep_str * star * "_order_rv_std")

annot = text.(orders[med_rvs_σ .< σ_floor], :center, :black, 3)
plt = my_scatter(orders[med_rvs_σ .< σ_floor], med_rvs_σ[med_rvs_σ .< σ_floor]; legend=:topleft, label="", title="$star Median σ", xlabel="Order", ylabel="m/s", size=(_plt_size[1]*0.5,_plt_size[2]*0.75), series_annotations=annot, ylim=[0,σ_floor])
annot = text.(orders[med_rvs_σ .> σ_floor], :center, :black, 3)
my_scatter!(plt, orders[med_rvs_σ .> σ_floor], ones(sum(med_rvs_σ .> σ_floor)) .* σ_floor; label="", series_annotations=annot, markershape=:utriangle, c=plt_colors[1])
png(plt, "neid_" * prep_str * star * "_order_rv_σ")

annot = text.(orders, :center, :black, 3)
plt = my_scatter(orders, std(rvs; dims=2) ./ med_rvs_σ; legend=:topleft, label="", title="$star (RV std) / (Median σ)", xlabel="Order", size=(_plt_size[1]*0.5,_plt_size[2]*0.75), series_annotations=annot)
png(plt, "neid_" * prep_str * star * "_order_rv_ratio")

χ² = vec(sum((rvs .- mean(rvs; dims=2)) .^ 2 ./ (rvs_σ .^ 2); dims=2))
annot = text.(orders[sortperm(χ²)], :center, :black, 4)
plt = my_scatter(1:length(χ²), sort(χ²); label="χ²", series_annotations=annot, legend=:topleft, title=prep_str * star * "_χ²") #, yaxis=:log)
png(plt, "neid_" * prep_str * star * "_χ²")

χ²_orders = sortperm(χ²)[1:end-20]
χ²_orders = [orders[χ²_order] for χ²_order in χ²_orders]
inds = orders2inds([orders[i] for i in eachindex(orders) if (med_rvs_σ[i] < σ_floor) && (orders[i] in χ²_orders)])

rvs_red = collect(Iterators.flatten((sum(rvs[inds, :] ./ (rvs_σ[inds, :] .^ 2); dims=1) ./ sum(1 ./ (rvs_σ[inds, :] .^ 2); dims=1))'))
rvs_red .-= median(rvs_red)
rvs_σ_red = collect(Iterators.flatten(1 ./ sqrt.(sum(1 ./ (rvs_σ[inds, :] .^ 2); dims=1)')))
rvs_σ2_red = rvs_σ_red .^ 2

@load SSOF_path * "/NEID/" * star * "_neid_pipeline.jld2" neid_time neid_rv neid_rv_σ
neid_rv .-= median(neid_rv)


mask = .!(2459525 .< times_nu .< 2459530)

# Compare RV differences to actual RVs from activity
plt = plot_model_rvs(times_nu[mask], rvs_red[mask], rvs_σ_red[mask], neid_time[mask], neid_rv[mask], neid_rv_σ[mask]; markerstrokewidth=1, title="HD$star (median σ: $(round(median(rvs_σ_red), digits=3)))")
png(plt, "neid_" * prep_str * star * "_model_rvs_mask.png")
# end

## regularization by order

@load "neid_$(prep_str)$(star)_regs.jld2" reg_tels reg_stars
reg_keys = SSOF._key_list[1:end-1]
mask = [reg_tels[i, 1]!=0 for i in 1:length(orders)]

plt = _my_plot(;xlabel="Order", ylabel="Regularization", title="Regularizations per order (HD$star)", yaxis=:log)
for i in eachindex(reg_keys)
    plot!(plt, orders[mask], reg_tels[mask, i], label="reg_$(reg_keys[i])", markershape=:circle, markerstrokewidth=0)
end
# for i in eachindex(reg_keys)
#     plot!(plt, orders, reg_stars[:, i], label="star_$(reg_keys[i])", markershape=:circle, markerstrokewidth=0)
# end
for i in eachindex(reg_keys)
    hline!(plt, [SSOF.default_reg_tel[reg_keys[i]]], c=plt_colors[i], label="")
    # hline!(plt, [SSOF.default_reg_star[reg_keys[i]]], c=plt_colors[i+length(reg_keys)], label="")
end
display(plt)
png(plt, "neid_" * prep_str * star * "_reg_tel")

plt = _my_plot(;xlabel="Order", ylabel="Regularization", title="Regularizations per order (HD$star)", yaxis=:log)
# for i in eachindex(reg_keys)
#     plot!(plt, orders, reg_tels[:, i], label="reg_$(reg_keys[i])", markershape=:circle, markerstrokewidth=0)
# end
for i in eachindex(reg_keys)
    plot!(plt, orders[mask], reg_stars[mask, i], label="star_$(reg_keys[i])", markershape=:circle, markerstrokewidth=0)
end
for i in eachindex(reg_keys)
    # hline!(plt, [SSOF.default_reg_tel[reg_keys[i]]], c=plt_colors[i], label="")
    hline!(plt, [SSOF.default_reg_star[reg_keys[i]]], c=plt_colors[i], label="")
end
display(plt)
png(plt, "neid_" * prep_str * star * "_reg_star")