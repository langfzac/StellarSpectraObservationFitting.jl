## Some helpful analysis functions
import StellarSpectraObservationFitting as SSOF
using JLD2
using Statistics
import StatsBase

valid_optimizers = ["adam", "l-bfgs"]

function create_model(
	data_fn::String,
	desired_order::Int,
	instrument::String,
	star::String;
	max_components::Int=5,
	oversamp::Bool=true,
	use_reg::Bool=true,
	save_fn::String="",
	recalc::Bool=false,
	seed::Union{SSOF.OrderModel, Nothing}=nothing
	)

	save = save_fn!=""
	seeded = !isnothing(seed)

	# save_path = save_path_base * star * "/$(desired_order)/"
	@load data_fn n_obs data times_nu airmasses
	data.var[data.var .== 0] .= Inf

	# takes a couple mins now
	if isfile(save_fn) && !recalc
		println("using saved model at $save_fn")
	    @load save_fn model
	    if model.metadata[:todo][:err_estimated]
	        @load save_fn rv_errors
	    end
	else
	    model = SSOF.OrderModel(data, instrument, desired_order, star; n_comp_tel=max_components, n_comp_star=max_components, oversamp=oversamp)
	    model, _, _, _, _ = SSOF.initialize!(model, data; seed=seed)
		# if seeded
		# 	pix = model.tel.log_λ.step.hi
		# 	proposed_shifts = -2pix:pix/10:2pix
		# 	holder = zeros(size(model.tel.lm.M[:,1]))
		# 	tel_shift_loss(s, shift) = SSOF.L2(s * view(model.tel.lm.M, :,1) - SSOF._spectra_interp_gp!(holder, model.tel.log_λ, view(seed.tel.lm.M, :, 1), SSOF.LSF_gp_var, seed.tel.log_λ .+ shift; gp_mean=0., gp_base=SSOF.LSF_gp))
		# 	pm = 2. * (tel_shift_loss(1., 0.) > tel_shift_loss(-1., 0.)) - 1.
		# 	losses = [tel_shift_loss(pm, shift) for shift in proposed_shifts]
		# 	ws = SSOF.ordinary_lst_sq(losses, 2; x=proposed_shifts)
		# 	proposed_shift_tel = -ws[2] / (2 * ws[3])
		# 	println()
		# 	println("shifted seeded tellurics by $(round(proposed_shift_tel*SSOF.light_speed_nu; digits=3)) m/s (~$(round(proposed_shift_tel/pix; digits=3)) model pix)")
		#
		# 	# pix = model.star.log_λ.step.hi
		# 	# proposed_shifts = -2pix:pix/10:2pix
		# 	# holder = zeros(size(model.star.lm.μ))
		# 	# star_shift_loss(shift) = SSOF.L2(model.star.lm.μ - SSOF._spectra_interp_gp!(holder, model.star.log_λ, seed.star.lm.μ, SSOF.SOAP_gp_var, seed.star.log_λ .+ shift; gp_base=SSOF.SOAP_gp))
		# 	# losses = [star_shift_loss(shift) for shift in proposed_shifts]
		# 	# ws = SSOF.ordinary_lst_sq(losses, 2; x=proposed_shifts)
		# 	# proposed_shift_star = -ws[2] / (2 * ws[3])
		# 	# println()
		# 	# println("shifted seeded star by $(round(proposed_shift_star*SSOF.light_speed_nu; digits=3)) m/s (~$(round(proposed_shift_star/pix; digits=3)) model pix)")
		#
		# 	SSOF._spectra_interp_gp!(model.star.lm.μ, model.star.log_λ, seed.star.lm.μ, SSOF.SOAP_gp_var, seed.star.log_λ .+ proposed_shift_star; gp_base=SSOF.SOAP_gp)
		# 	SSOF._spectra_interp_gp!(model.tel.lm.μ, model.tel.log_λ, seed.tel.lm.μ, SSOF.LSF_gp_var, seed.tel.log_λ .+ proposed_shift_tel; gp_base=SSOF.LSF_gp)
		# 	if SSOF.is_time_variable(seed.tel)
		# 		n_comp_tel = size(seed.tel.lm.M, 2)
		# 		model = SSOF.downsize(model, n_comp_tel, max_components)
		# 		for i in 1:n_comp_tel
		# 			SSOF._spectra_interp_gp!(view(model.tel.lm.M, :, i), model.tel.log_λ, view(seed.tel.lm.M, :, i), SSOF.LSF_gp_var, seed.tel.log_λ .+ proposed_shift_tel; gp_mean=0., gp_base=SSOF.LSF_gp)
		# 		end
		# 	else
		# 		model = SSOF.downsize(model, 0, max_components)
		# 	end
		# end
		if !use_reg
			SSOF.rm_regularization!(model)
			model.metadata[:todo][:reg_improved] = true
		end
		if save; @save save_fn model end
	end
	return model, data, times_nu, airmasses
end

function create_workspace(model, data, opt::String; seeded::Bool=false)
	@assert opt in valid_optimizers
	if opt == "l-bfgs"
		mws = SSOF.OptimWorkspace(model, data)
	elseif seeded
		mws = SSOF.FrozenTelWorkspace(model, data)
	else
		mws = SSOF.TotalWorkspace(model, data)
	end
	return mws
end

function improve_regularization!(mws; redo::Bool=false, print_stuff::Bool=true, testing_ratio::Real=0.25, save_fn::String="")

	save = save_fn!=""

	model = mws.om
	if redo || !model.metadata[:todo][:reg_improved]  # 27 mins
		@assert 0 < testing_ratio < 1
		n_obs = size(mws.d.flux, 2)

	    SSOF.train_OrderModel!(mws; print_stuff=print_stuff, ignore_regularization=true)  # 45s
	    n_obs_test = Int(round(testing_ratio * n_obs))
	    test_start_ind = max(1, Int(round(rand() * (n_obs - n_obs_test))))
	    testing_inds = test_start_ind:test_start_ind+n_obs_test-1
	    SSOF.fit_regularization!(mws, testing_inds)
	    model.metadata[:todo][:reg_improved] = true
	    model.metadata[:todo][:optimized] = false
	    if save; @save save_fn model end
	end
end

function improve_model!(mws; print_stuff::Bool=true, show_plot::Bool=false, save_fn::String="", kwargs...)
	save = save_fn!=""
	model = mws.om
	if !model.metadata[:todo][:optimized]
	    SSOF.train_OrderModel!(mws; print_stuff=print_stuff, kwargs...)  # 120s
		SSOF.finalize_scores!(mws)
	    if show_plot; status_plot(mws) end
	    model.metadata[:todo][:optimized] = true
	    if save; @save save_fn model end
	end
end

function downsize_model(mws, times; save_fn::String="", decision_fn::String="", print_stuff::Bool=true, plots_fn::String="")
	save = save_fn!=""
	save_md = decision_fn!=""
	save_plots = plots_fn!=""
	model = mws.om

	if !model.metadata[:todo][:downsized]  # 1.5 hrs (for 9x9)
	    test_n_comp_tel = 0:size(model.tel.lm.M, 2)
	    test_n_comp_star = 0:size(model.star.lm.M, 2)
	    ks = zeros(Int, length(test_n_comp_tel), length(test_n_comp_star))
	    comp_ls = zeros(length(test_n_comp_tel), length(test_n_comp_star))
	    comp_stds = zeros(length(test_n_comp_tel), length(test_n_comp_star))
	    comp_intra_stds = zeros(length(test_n_comp_tel), length(test_n_comp_star))
	    for (i, n_tel) in enumerate(test_n_comp_tel)
	        for (j, n_star) in enumerate(test_n_comp_star)
	            comp_ls[i, j], ks[i, j], comp_stds[i, j], comp_intra_stds[i, j] = SSOF.test_ℓ_for_n_comps([n_tel, n_star], mws, times)
	        end
	    end
	    n_comps_best, ℓ, aics, bics = SSOF.choose_n_comps(comp_ls, ks, test_n_comp_tel, test_n_comp_star, mws.d.var; return_inters=true)
	    if save_md; @save decision_fn comp_ls ℓ aics bics ks test_n_comp_tel test_n_comp_star comp_stds comp_intra_stds end

	    model_large = copy(model)
	    model = SSOF.downsize(model, n_comps_best[1], n_comps_best[2])
	    model.metadata[:todo][:downsized] = true
	    model.metadata[:todo][:reg_improved] = true
	    mws_smol = typeof(mws)(model, mws.d)
	    SSOF.train_OrderModel!(mws_smol; print_stuff=print_stuff)  # 120s
	    SSOF.finalize_scores!(mws_smol)
	    model.metadata[:todo][:optimized] = true
	    if save; @save save_fn model model_large end

		if save_plots
			diagnostics = [ℓ, aics, bics, comp_stds, comp_intra_stds]
			diagnostics_labels = ["ℓ", "AIC", "BIC", "RV std", "Intra-night RV std"]
			diagnostics_fn = ["l", "aic", "bic", "rv", "rv_intra"]
			for i in 1:length(diagnostics)
				plt = component_test_plot(diagnostics[i], test_n_comp_tel, test_n_comp_star, ylabel=diagnostics_labels[i]);
				png(plt, plots_fn * diagnostics_fn[i] * "_choice.png")
			end
		end
		return mws_smol, ℓ, aics, bics, comp_stds, comp_intra_stds
	end
end
function _downsize_model(mws, n_comps_tel::Int, n_comps_star::Int, print_stuff::Bool=true)
	model = SSOF.downsize(mws.om, n_comps_tel, n_comps_star)
	mws_smol = typeof(mws)(model, mws.d)
	SSOF.train_OrderModel!(mws_smol; print_stuff=print_stuff)  # 120s
	SSOF.finalize_scores!(mws_smol)
	return mws_smol
end

function estimate_errors(mws; save_fn="")
	save = save_fn!=""
	model = mws.om
	data = mws.d
	if !model.metadata[:todo][:err_estimated] # 25 mins
	    data.var[data.var.==Inf] .= 0
	    data_noise = sqrt.(data.var)
	    data.var[data.var.==0] .= Inf

		rvs = SSOF.rvs(model)
	    n = 50
	    rv_holder = Array{Float64}(undef, n, length(model.rv.lm.s))
	    _mws = typeof(mws)(copy(model), copy(data))
	    _mws_score_finalizer() = SSOF.finalize_scores_setup(_mws)
	    for i in 1:n
	        _mws.d.flux .= data.flux .+ (data_noise .* randn(size(data.var)))
	        SSOF.train_OrderModel!(_mws; iter=50)
	        _mws_score_finalizer()
	        rv_holder[i, :] = SSOF.rvs(_mws.om)
	    end
	    rv_errors = vec(std(rv_holder; dims=1))
	    model.metadata[:todo][:err_estimated] = true
	    if save; @save save_fn model rvs rv_errors end
		return rvs, rv_errors
	end
end
