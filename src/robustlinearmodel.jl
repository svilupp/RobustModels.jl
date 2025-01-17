

######
##    TableRegressionModel methods to forward
######
@delegate TableRegressionModel.model [
    leverage,
    weights,
    workingweights,
    dispersion,
    scale,
    tauscale,
    fitted,
    isfitted,
    islinear,
    Estimator,
    projectionmatrix,
    hasintercept,
]

fit!(p::TableRegressionModel, args...; kwargs...) = (fit!(p.model, args...; kwargs...); p)
refit!(p::TableRegressionModel, args...; kwargs...) =
    (refit!(p.model, args...; kwargs...); p)



"""
    RobustLinearModel

Robust linear model representation

## Fields

* `resp`: the [`RobustLinResp`](@ref) structure.
* `pred`: the predictor structure, of type [`DensePredChol`](@ref), [`SparsePredChol`](@ref), [`DensePredCG`](@ref), [`SparsePredCG`](@ref) or [`RidgePred`](@ref).
* `fitdispersion`: if true, the dispersion is estimated otherwise it is kept fixed
* `fitted`: if true, the model was already fitted
"""
mutable struct RobustLinearModel{T<:AbstractFloat,R<:RobustResp{T},L<:LinPred} <:
               AbstractRobustModel{T}
    resp::R
    pred::L
    fitdispersion::Bool
    fitted::Bool
end

function Base.getproperty(
    r::TableRegressionModel{M},
    s::Symbol,
) where {M<:RobustLinearModel}
    if s ∈ (:resp, :pred, :fitdispersion, :fitted)
        getproperty(r.model, s)
    else
        getfield(r, s)
    end
end


######
##    AbstractRobustModel methods
######

dof(m::AbstractRobustModel) = length(coef(m))

dof_residual(m::AbstractRobustModel) = nobs(m) - dof(m)

function coeftable(m::AbstractRobustModel; level::Real=0.95)
    cc = coef(m)
    se = stderror(m)
    tt = cc ./ se
    ci = se * quantile(TDist(dof_residual(m)), (1 - level) / 2)
    p = ccdf.(Ref(FDist(1, dof_residual(m))), abs2.(tt))
    levstr = isinteger(level * 100) ? string(Integer(level * 100)) : string(level * 100)
    CoefTable(
        hcat(cc, se, tt, p, cc + ci, cc - ci),
        ["Coef.", "Std. Error", "t", "Pr(>|t|)", "Lower $(levstr)%", "Upper $(levstr)%"],
        ["x$i" for i in 1:length(cc)],
        4,
        3,
    )
end

function confint(m::AbstractRobustModel; level::Real=0.95)
    alpha = quantile(TDist(dof_residual(m)), (1 - level) / 2)
    hcat(coef(m), coef(m)) + stderror(m) * alpha * hcat(1.0, -1.0)
end
confint(m::AbstractRobustModel, level::Real) = confint(m; level=level)

## TODO: specialize to make it faster
leverage(p::AbstractRobustModel) = diag(projectionmatrix(p))

######
##    RobustLinearModel methods
######

function show(io::IO, obj::RobustLinearModel)
    println(io, "Robust regression with $(obj.resp.est)\n\nCoefficients:\n", coeftable(obj))
end

function show(io::IO, obj::TableRegressionModel{M,T}) where {T,M<:RobustLinearModel}
    println(
        io,
        "Robust regression with $(obj.model.resp.est)\n\n$(obj.mf.f)\n\nCoefficients:\n",
        coeftable(obj),
    )
end

islinear(m::RobustLinearModel) = true

"""
    deviance(m::RobustLinearModel)

The sum of twice the loss/objective applied to the scaled residuals.

It is consistent with the definition of the deviance for OLS.
"""
deviance(m::RobustLinearModel) = deviance(m.resp)

nulldeviance(m::RobustLinearModel) = nulldeviance(m.resp; intercept=hasintercept(m.pred))

"""
    dispersion(m::RobustLinearModel, sqr::Bool=false)

The dispersion is the (weighted) sum of robust residuals. If `sqr` is true, return the squared dispersion.
"""
dispersion(m::RobustLinearModel, sqr::Bool=false) = dispersion(m.resp, dof_residual(m), sqr)


nobs(m::RobustLinearModel)::Int = nobs(m.resp)

coef(m::RobustLinearModel) = coef(m.pred)

"""
    Estimator(m::RobustLinearModel)

The robust estimator object used to fit the model.
"""
Estimator(m::RobustLinearModel) = Estimator(m.resp)

stderror(m::RobustLinearModel) =
    location_variance(m.resp, dof_residual(m), false) .* sqrt.(diag(vcov(m)))

loglikelihood(m::RobustLinearModel) = loglikelihood(m.resp)

nullloglikelihood(m::RobustLinearModel) = nullloglikelihood(m.resp; intercept=hasintercept(m.pred))

weights(m::RobustLinearModel) = weights(m.resp)

"""
    workingweights(m::RobustLinearModel)

The robust weights computed by the model.

This can be used to detect outliers, as outliers weights are lower than the
weights of valid data points.
"""
workingweights(m::RobustLinearModel) = workingweights(m.resp)

response(m::RobustLinearModel) = response(m.resp)

isfitted(m::RobustLinearModel) = m.fitted

fitted(m::RobustLinearModel) = fitted(m.resp)

residuals(m::RobustLinearModel) = residuals(m.resp)

"""
    scale(m::RobustLinearModel, sqr::Bool=false)

The robust scale estimate used for the robust estimation.

If `sqr` is `true`, the square of the scale is returned.
"""
scale(m::RobustLinearModel, sqr::Bool=false) = scale(m.resp, sqr)

"""
    tauscale(m::RobustLinearModel, sqr::Bool=false; kwargs...)

The robust τ-scale that is minimized in τ-estimation.

If `sqr` is `true`, the square of the τ-scale is returned.
"""
tauscale(m::RobustLinearModel, args...; kwargs...) = tauscale(m.resp, args...; kwargs...)

modelmatrix(m::RobustLinearModel) = modelmatrix(m.pred)

vcov(m::RobustLinearModel) = vcov(m.pred, workingweights(m.resp))

"""
    projectionmatrix(m::RobustLinearModel)

The robust projection matrix from the predictor: X (X' W X)⁻¹ X' W
"""
projectionmatrix(m::RobustLinearModel) = projectionmatrix(m.pred, workingweights(m.resp))

function leverage_weights(m::RobustLinearModel)
    w = weights(m.resp)
    v = inv(Hermitian(float(modelmatrix(m)' * (w .* modelmatrix(m)))))
    h = diag(Hermitian(modelmatrix(m) * v * modelmatrix(m)' .* w))
    sqrt.(1 .- h)
end

hasintercept(m::RobustLinearModel) = hasintercept(m.pred)

## RobustLinearModel fit methods

function predict(
    m::RobustLinearModel,
    newX::AbstractMatrix;
    offset::FPVector=eltype(newX)[],
)
    mu = newX * coef(m)
    if !isempty(m.resp.offset)
        if !(length(offset) == size(newX, 1))
            mess =
                "fit with offset, so `offset` keyword argument" *
                " must be an offset of length `size(newX, 1)`"
            throw(ArgumentError(mess))
        end
        broadcast!(+, mu, mu, offset)
    else
        if length(offset) > 0
            mess = "fit without offset, so value of `offset` kwarg does not make sense"
            throw(ArgumentError(mess))
        end
    end
    mu
end
predict(m::RobustLinearModel) = fitted(m)


"""
    rlm(X, y, args...; kwargs...)

An alias for `fit(RobustLinearModel, X, y, est; kwargs...)`.

The arguments `X` and `y` can be a `Matrix` and a `Vector` or a `Formula` and a `DataFrame`.
"""
rlm(X, y, args...; kwargs...) = fit(RobustLinearModel, X, y, args...; kwargs...)


"""
    fit(::Type{M},
        X::Union{AbstractMatrix{T},SparseMatrixCSC{T}},
        y::AbstractVector{T},
        est::Estimator;
        method::Symbol       = :chol, # :cg
        dofit::Bool          = true,
        wts::FPVector        = similar(y, 0),
        offset::FPVector     = similar(y, 0),
        fitdispersion::Bool  = false,
        ridgeλ::Real         = 0,
        ridgeG::Union{UniformScaling, AbstractArray} = I,
        βprior::AbstractVector = [],
        quantile::Union{Nothing, AbstractFloat} = nothing,
        initial_scale::Union{Symbol, Real}=:mad,
        σ0::Union{Nothing, Symbol, Real}=initial_scale,
        initial_coef::AbstractVector=[],
        β0::AbstractVector=initial_coef,
        correct_leverage::Bool=false
        fitargs...) where {M<:RobustLinearModel, T<:AbstractFloat}

Create a robust model with the model matrix (or formula) X and response vector (or dataframe) y,
using a robust estimator.


# Arguments

- `X`: the model matrix (it can be dense or sparse) or a formula
- `y`: the response vector or a dataframe.
- `est`: a robust estimator

# Keywords

- `method::Symbol = :chol`: the method to use for solving the weighted linear system, `chol` (default) or `cg`;
- `dofit::Bool = true`: if false, return the model object without fitting;
- `wts::Vector = []`: a weight vector, should be empty if no weights are used;
- `offset::Vector = []`: an offset vector, should be empty if no offset is used;
- `fitdispersion::Bool = false`: reevaluate the dispersion;
- `ridgeλ::Real = 0`: if positive, perform a robust ridge regression with shrinkage parameter `ridgeλ`. [`RidgePred`](@ref) object will be used;
- `ridgeG::Union{UniformScaling, AbstractArray} = I`: define a custom regularization matrix. Default to unity matrix (with 0 for the intercept);
- `βprior::AbstractVector = []`: define a custom prior for the coefficients for ridge regression. Default to `zeros(p)`;
- `quantile::Union{Nothing, AbstractFloat} = nothing`: only for [`GeneralizedQuantileEstimator`](@ref), define the quantile to estimate;
- `initial_scale::Union{Symbol, Real}=:mad`: the initial scale estimate, for non-convex estimator it helps to find the global minimum. Automatic computation using `:mad`, `L1` or `extrema` (non-robust).
- `σ0::Union{Nothing, Symbol, Real}=initial_scale`: alias of `initial_scale`;
- `initial_coef::AbstractVector=[]`: the initial coefficients estimate, for non-convex estimator it helps to find the global minimum.
- `β0::AbstractVector=initial_coef`: alias of `initial_coef`;
- `correct_leverage::Bool=false`: apply the leverage correction weights with [`leverage_weights`](@ref).
- `fitargs...`: other keyword arguments used to control the convergence of the IRLS algorithm (see [`pirls!`](@ref)).

# Output

the RobustLinearModel object.

"""
function fit(
    ::Type{M},
    X::Union{AbstractMatrix{T},SparseMatrixCSC{T}},
    y::AbstractVector{T},
    est::V;
    method::Symbol=:chol, # :cg
    dofit::Bool=true,
    wts::FPVector=similar(y, 0),
    offset::FPVector=similar(y, 0),
    fitdispersion::Bool=false,
    ridgeλ::Real=0,
    ridgeG::Union{UniformScaling,AbstractArray}=I,
    βprior::AbstractVector=[],
    quantile::Union{Nothing,AbstractFloat}=nothing,
    fitargs...,
) where {M<:RobustLinearModel,V<:AbstractEstimator,T<:AbstractFloat}

    # Check that X and y have the same number of observations
    n, p = size(X)
    if n != size(y, 1)
        throw(DimensionMismatch("number of rows in X and y must match"))
    end

    # Change quantile
    if !isnothing(quantile)
        if !isa(est, AbstractQuantileEstimator)
            throw(
                TypeError(
                    :fit,
                    "arguments, quantile can be changed only if isa(est, AbstractQuantileEstimator)",
                    AbstractQuantileEstimator,
                    est,
                ),
            )
        end
        est.quantile = quantile
    end

    # Response object
    rr = RobustLinResp(est, y, offset, wts)

    # Predictor object
    pp = if ridgeλ > 0
        # With ridge regularization
        G = if isa(ridgeG, UniformScaling)
            # Has an intersect
            if _hasintercept(X)
                spdiagm(0 => [float(i != 1) for i in 1:p])
            else
                I(p)
            end
        else
            ridgeG
        end
        if method == :cg
            cgpred(X, float(ridgeλ), G, βprior)
        else
            cholpred(X, float(ridgeλ), G, βprior)
        end
    else
        # No regularization
        if method == :cg
            cgpred(X)
        else
            cholpred(X)
        end
    end

    m = RobustLinearModel(rr, pp, fitdispersion, false)
    return dofit ? fit!(m; fitargs...) : m
end

function fit(
    ::Type{M},
    X::Union{AbstractMatrix,SparseMatrixCSC},
    y::AbstractVector,
    est::AbstractEstimator;
    kwargs...,
) where {M<:AbstractRobustModel}
    fit(M, float(X), float(y), est; kwargs...)
end


"""
    refit!(m::RobustLinearModel, [y::FPVector];
                                 wts::Union{Nothing, FPVector} = nothing,
                                 offset::Union{Nothing, FPVector} = nothing,
                                 quantile::Union{Nothing, AbstractFloat} = nothing,
                                 ridgeλ::Union{Nothing, Real} = nothing,
                                 kwargs...)

Refit the [`RobustLinearModel`](@ref).

This function assumes that `m` was correctly initialized and the model is refitted with
the new values for the response, weights, offset, quantile and ridge shrinkage.

Defining a new `quantile` is only possible for [`GeneralizedQuantileEstimator`](@ref).

Defining a new `ridgeλ` is only possible for [`RidgePred`](@ref) objects.
"""
function refit!(m::RobustLinearModel, y::FPVector; kwargs...)
    r = m.resp
    # Check that old and new y have the same number of observations
    if size(r.y, 1) != size(y, 1)
        mess = "the new response vector should have the same dimension: "*
               "$(size(r.y, 1)) != $(size(y, 1))"
        throw(DimensionMismatch(mess))
    end
    # Update y
    copyto!(r.y, y)

    refit!(m; kwargs...)
end

function refit!(
    m::RobustLinearModel{T};
    wts::Union{Nothing,FPVector}=nothing,
    offset::Union{Nothing,FPVector}=nothing,
    quantile::Union{Nothing,AbstractFloat}=nothing,
    ridgeλ::Union{Nothing,Real}=nothing,
    kwargs...,
) where {T}

    if haskey(kwargs, :method)
        @warn("the method cannot be changed when refitting,"*
              " ignore the method argument $(kwargs[:method])."
        )
        delete!(kwargs, :method)
    end

    r = m.resp

    n = length(r.y)
    if !isa(wts, Nothing) && (length(wts) in (0, n))
        copy!(r.wts, wts)
    end
    if !isa(offset, Nothing) && (length(offset) in (0, n))
        copy!(r.offset, offset)
    end

    # Update quantile, if the estimator is AbstractQuantileEstimator
    if !isnothing(quantile)
        isa(r.est, AbstractQuantileEstimator) || throw(
            TypeError(
                :refit!,
                "arguments, quantile can be changed only if isa(r.est, AbstractQuantileEstimator)",
                AbstractQuantileEstimator,
                r.est,
            ),
        )
        r.est.quantile = quantile
    end

    # Update ridge shrinkage parameter
    if !isnothing(ridgeλ)
        isa(m.pred, RidgePred) || throw(
            TypeError(
                :refit!,
                "arguments, ridgeλ can be changed only if the predictor is a RidgePred",
                RidgePred,
                m.pred,
            ),
        )
        m.pred.λ = float(ridgeλ)
        # reset beta0 because it needs to be zero for the first estimation
        resetβ0!(m.pred)
    end

    # Reinitialize the coefficients and the response
    fill!(coef(m), zero(T))
    initresp!(r)

    m.fitted = false
    fit!(m; kwargs...)
end


"""
    fit!(m::RobustLinearModel; initial_scale::Union{Symbol, Real}=:mad,
              σ0::Union{Nothing, Symbol, Real}=initial_scale,
              initial_coef::AbstractVector=[],
              β0::AbstractVector=initial_coef,
              correct_leverage::Bool=false, kwargs...)

Optimize the objective of a `RobustLinearModel`.  When `verbose` is `true` the values of the
objective and the parameters are printed on stdout at each iteration.

This function assumes that `m` was correctly initialized.

This function returns early if the model was already fitted, instead call `refit!`.
"""
function fit!(
    m::RobustLinearModel;
    initial_scale::Union{Symbol,Real}=:mad,
    σ0::Union{Nothing,Symbol,Real}=initial_scale,
    initial_coef::AbstractVector=[],
    β0::AbstractVector=initial_coef,
    correct_leverage::Bool=false,
    kwargs...,
)

    # Return early if model has the fit flag set
    m.fitted && return m

    # Compute the initial values
    σ0, β0 = process_σ0β0(m, σ0, β0)

    if correct_leverage
        wts = m.resp.wts
        copy!(wts, leverage_weights(m))
        ## TODO: maybe multiply by the old wts?
    end

    # Get type
    V = typeof(m.resp.est)

    _fit!(m, V; σ0=σ0, β0=β0, kwargs...)

    m.fitted = true
    m
end

## Error message
function _fit!(m::RobustLinearModel, ::Type{E}; kwargs...) where {E<:AbstractEstimator}
    allowed_estimators =
        (MEstimator, SEstimator, MMEstimator, TauEstimator, GeneralizedQuantileEstimator)
    mess = "only types $(allowed_estimators) are allowed, "*
           "you must define the `_fit!` method for the type: $(E)"
    error(mess)
end

# Fit M-estimator
function _fit!(
    m::RobustLinearModel,
    ::Type{E};
    σ0::AbstractFloat=1.0,
    β0::AbstractVector=[],
    verbose::Bool=false,
    kwargs...,
) where {E<:MEstimator}

    verbose && println("\nFit with M-estimator: $(Estimator(m))")
    ## Minimize the objective
    pirls!(m; sigma0=σ0, beta0=β0, verbose=verbose, kwargs...)

    ## TODO: update scale is fitdispersion is true
    m
end

# Fit Generalized M-Quantile estimator
function _fit!(
    m::RobustLinearModel,
    ::Type{E};
    σ0::AbstractFloat=1.0,
    β0::AbstractVector=[],
    verbose::Bool=false,
    kwargs...,
) where {E<:GeneralizedQuantileEstimator}

    verbose && println("\nFit with M-Quantile-estimator: $(Estimator(m))")
    ## Minimize the objective
    pirls!(m; sigma0=σ0, beta0=β0, verbose=verbose, kwargs...)

    ## TODO: update scale if fitdispersion is true
    m
end

# Fit S-estimator
function _fit!(
    m::RobustLinearModel,
    ::Type{E};
    σ0::AbstractFloat=1.0,
    β0::AbstractVector=[],
    verbose::Bool=false,
    resample::Bool=false,
    resampling_options::Dict{Symbol,F}=Dict{Symbol,Any}(:verbose => verbose),
    kwargs...,
) where {F,E<:SEstimator}

    ## Resampling algorithm to find a starting point close to the global minimum
    if resample
        σ0, β0 = resampling_best_estimate(m, E; resampling_options...)
    end

    verbose && println("\nFit with S-estimator: $(Estimator(m))")
    ## Minimize the objective
    pirls_Sestimate!(m; sigma0=σ0, beta0=β0, verbose=verbose, kwargs...)

    # Set the `fitdispersion` flag to true, because σ was estimated
    m.fitdispersion = true

    m
end

# Fit MM-estimator
function _fit!(
    m::RobustLinearModel,
    ::Type{E};
    σ0::AbstractFloat=1.0,
    β0::AbstractVector=[],
    verbose::Bool=false,
    resample::Bool=false,
    resampling_options::Dict{Symbol,F}=Dict{Symbol,Any}(:verbose => verbose),
    kwargs...,
) where {F,E<:MMEstimator}

    ## Set the S-Estimator for robust estimation of σ and β0
    set_SEstimator(Estimator(m.resp))

    ## Resampling algorithm to find a starting point close to the global minimum
    if resample
        σ0, β0 = resampling_best_estimate(m, E; resampling_options...)
    end

    verbose && println("\nFit with MM-estimator - 1. S-estimator: $(Estimator(m.resp))")
    ## Minimize the objective
    pirls_Sestimate!(m; sigma0=σ0, beta0=β0, verbose=verbose, kwargs...)

    ## Use an M-estimate to estimate coefficients
    β0 = coef(m)
    σ0 = scale(m)

    ## Set the M-Estimator for efficient estimation of β
    set_MEstimator(Estimator(m.resp))

    verbose && println("\nFit with MM-estimator - 2. M-estimator: $(Estimator(m.resp))")
    ## Minimize the objective
    pirls!(m; sigma0=σ0, beta0=β0, verbose=verbose, kwargs...)

    # Set the `fitdispersion` flag to true, because σ was estimated
    m.fitdispersion = true

    m
end

# Fit τ-estimator
function _fit!(
    m::RobustLinearModel,
    ::Type{E};
    σ0::AbstractFloat=1.0,
    β0::AbstractVector=[],
    verbose::Bool=false,
    resample::Bool=false,
    resampling_options::Dict{Symbol,F}=Dict{Symbol,Any}(:verbose => verbose),
    kwargs...,
) where {F,E<:TauEstimator}

    ## Resampling algorithm to find a starting point close to the global minimum
    if resample
        σ0, β0 = resampling_best_estimate(m, E; resampling_options...)
    end

    verbose && println("\nFit with τ-estimator: $(Estimator(m))")
    ## Minimize the objective
    pirls_τestimate!(m; sigma0=σ0, beta0=β0, verbose=verbose, kwargs...)

    # Set the `fitdispersion` flag to true, because σ was estimated
    m.fitdispersion = true

    m
end

function process_σ0β0(
    m::RobustLinearModel,
    σ0::Union{Real,Symbol}=scale(m),
    β0::AbstractVector=[],
)
    # Process scale σ0
    σ0 = if isa(σ0, Real)
        float(σ0)
    elseif isa(σ0, Symbol)
        initialscale(m, σ0)
    end

    # Process coefficients β0
    β0 = if isempty(β0) || size(β0, 1) != size(coef(m), 1)
        []
    else
        float(β0)
    end

    return σ0, β0
end

function initialscale(m::RobustLinearModel, method::Symbol=:mad; factor::AbstractFloat=1.0)
    factor > 0 || error("factor should be positive")

    y = response(m)
    wts = Vector(weights(m))

    allowed_methods = (:mad, :extrema, :L1)
    if method == :mad
        σ = if length(wts) == length(y)
            factor * mad(wts .* y; normalize=true)
        else
            factor * mad(y; normalize=true)
        end
    elseif method == :L1
        X = modelmatrix(m)
        σ = dispersion(quantreg(X, y; wts=wts))
    elseif method == :extrema
        # this is not robust
        σ = -(-(extrema(y)...)) / 2
    else
        error("only $(join(allowed_methods, ", ", " and ")) methods are allowed")
    end
    return σ
end

function setβ0!(m::RobustLinearModel{T}, β0::AbstractVector=[]) where {T<:AbstractFloat}
    r = m.resp
    p = m.pred

    initresp!(r)
    if isempty(β0)
        # Compute beta0 from solving the least square with the response value r.y
        # initresp!(r)
        delbeta!(p, r.wrkres, r.wrkwt)
        installbeta!(p)
    else
        copyto!(p.beta0, float(β0))
        fill!(p.delbeta, 0)
    end

    m
end

"""
    setinitη!(m)
Compute the predictor using the initial value of β0 and compute the residuals
"""
function setinitη!(m::RobustLinearModel{T}) where {T}
    r = m.resp
    p = m.pred

    ## Initially, β0 is defined but not ∇β, so use f=0
    linpred!(r.η, p, 0)
    updateres!(r; updatescale=false)

    m
end

"""
    setinitσ!(m)
Compute the predictor scale using the MAD of the residuals
Use only for rough estimate, like in the resampling phase.
"""
function setinitσ!(m::RobustLinearModel; kwargs...)
    m.resp.σ = madresidualscale(m.resp; kwargs...)
    m
end

"""
    setη!(m, f=1.0; updatescale=false, kwargs...)
Compute the ∇β using the current residuals and working weights (only if f=1,
which corresponds to the first iteration of linesearch), then compute
the predictor using the ∇β value and compute the new residuals and deviance.
The scaletype argument defines if the location or scale loss function should be used
If updatescale is true, the scale is also updated along with the residuals.
"""
function setη!(
    m::RobustLinearModel{T},
    f::T=1.0;
    updatescale::Bool=false,
    kwargs...,
) where {T}
    r = m.resp
    p = m.pred

    # First update of linesearch algorithm, compute ∇β
    if f == 1
        delbeta!(p, r.wrkres, r.wrkwt)
    end
    # Compute and set the predictor η from β0 and ∇β
    linpred!(r.η, p, f)

    # Update the residuals and weights (and scale if updatescale=true)
    updateres!(r; updatescale=updatescale, kwargs...)
    m
end



"""
    pirls!(m::RobustLinearModel{T}; verbose::Bool=false, maxiter::Integer=30,
           minstepfac::Real=1e-3, atol::Real=1e-6, rtol::Real=1e-6,
           beta0::AbstractVector=[], sigma0::Union{Nothing, T}=nothing)

(Penalized) Iteratively Reweighted Least Square procedure for M-estimation.
The Penalized aspect is not implemented (yet).
"""
function pirls!(
    m::RobustLinearModel{T};
    verbose::Bool=false,
    maxiter::Integer=30,
    minstepfac::Real=1e-3,
    atol::Real=1e-6,
    rtol::Real=1e-5,
    beta0::AbstractVector=[],
    sigma0::Union{Nothing,T}=nothing,
) where {T<:AbstractFloat}

    # Check arguments
    maxiter >= 1 || throw(ArgumentError("maxiter must be positive"))
    0 < minstepfac < 1 || throw(ArgumentError("minstepfac must be in (0, 1)"))

    # Extract fields and set convergence flag
    cvg, p, r = false, m.pred, m.resp

    ## Initialize σ, default to do not change
    if !isnothing(sigma0)
        r.σ = sigma0
    end

    ## Initialize β or set it to the provided values
    setβ0!(m, beta0)

    # Initialize μ and compute residuals
    setinitη!(m)

    # If σ==0, iterations will fail, so return here
    if iszero(r.σ)
        verbose && println("Initial scale is 0.0, no iterations performed.")
        return m
    end

    # Compute initial deviance
    devold = deviance(m)
    absdev = abs(devold)
    dev = devold
    Δdev = 0

    verbose && println("initial deviance: $(@sprintf("%.4g", devold))")
    for i in 1:maxiter
        f = 1.0 # line search factor
        # local dev
        absdev = abs(devold)

        # Compute the change to β, update μ and compute deviance
        dev = try
            deviance(setη!(m; updatescale=false))
        catch e
            isa(e, DomainError) ? Inf : rethrow(e)
        end

        # Assert the deviance is positive (up to rounding error)
        @assert dev > -atol

        verbose && println(
            "deviance at step $i: $(@sprintf("%.4g", dev)), crit=$((devold - dev)/absdev)",
        )

        # Line search
        ## If the deviance isn't declining then half the step size
        ## The rtol*abs(devold) term is to avoid failure when deviance
        ## is unchanged except for rounding errors.
        while dev > devold + rtol * absdev
            f /= 2
            f > minstepfac ||
                error("linesearch failed at iteration $(i) with beta0 = $(p.beta0)")

            dev = try
                # Update μ and compute deviance with new f. Do not recompute ∇β
                deviance(setη!(m, f))
            catch e
                isa(e, DomainError) ? Inf : rethrow(e)
            end
        end
        installbeta!(p, f)

        # Test for convergence
        Δdev = (devold - dev)
        verbose && println("Iteration: $i, deviance: $dev, Δdev: $(Δdev)")
        tol = max(rtol * absdev, atol)
        if -tol < Δdev < tol || dev < atol
            cvg = true
            break
        end
        @assert isfinite(dev)
        devold = dev
    end
    cvg || throw(ConvergenceException(maxiter))
    m
end


"""
    pirls_Sestimate!(m::RobustLinearModel{T}; verbose::Bool=false, maxiter::Integer=30,
           minstepfac::Real=1e-3, atol::Real=1e-6, rtol::Real=1e-6,
           beta0::AbstractVector=T[], sigma0::Union{Nothing, T}=nothing)

(Penalized) Iteratively Reweighted Least Square procedure for S-estimation.
The Penalized aspect is not implemented (yet).
"""
function pirls_Sestimate!(
    m::RobustLinearModel{T};
    verbose::Bool=false,
    maxiter::Integer=30,
    minstepfac::Real=1e-3,
    atol::Real=1e-6,
    rtol::Real=1e-5,
    miniter::Int=2,
    beta0::AbstractVector=[],
    sigma0::Union{Nothing,T}=nothing,
) where {T<:AbstractFloat}

    # Check arguments
    maxiter >= 1 || throw(ArgumentError("maxiter must be positive"))
    0 < minstepfac < 1 || throw(ArgumentError("minstepfac must be in (0, 1)"))

    # Extract fields and set convergence flag
    cvg, p, r = false, m.pred, m.resp

    ## Initialize σ, default to largest value
    maxσ = -(-(extrema(r.y)...)) / 2
    if !isnothing(sigma0)
        r.σ = sigma0
    else
        r.σ = maxσ
    end

    ## Initialize β or set it to the provided values
    setβ0!(m, beta0)

    # Initialize μ and compute residuals
    setinitη!(m)

    # Compute initial scale
    sigold =
        scale(setη!(m; updatescale=true, verbose=verbose, sigma0=sigma0, fallback=maxσ))
    installbeta!(p, 1)
    r.σ = sigold

    verbose && println("initial scale: $(@sprintf("%.4g", sigold))")
    for i in 1:maxiter
        f = 1.0 # line search factor
        local sig

        # Compute the change to β, update μ and compute deviance
        sig =
            scale(setη!(m; updatescale=true, verbose=verbose, sigma0=sigold, fallback=maxσ))

        # Assert the deviance is positive (up to rounding error)
        @assert sig > -atol

        verbose && println(
            "scale at step $i: $(@sprintf("%.4g", sig)), crit=$((sigold - sig)/sigold)",
        )

        # Line search
        ## If the scale isn't declining then half the step size
        ## The rtol*abs(sigold) term is to avoid failure when scale
        ## is unchanged except for rounding errors.
        while sig > sigold * (1 + rtol)
            f /= 2
            if f <= minstepfac
                if i <= miniter
                    sigold = maxσ
                    r.σ = sigold
                    verbose && println(
                        "linesearch failed at early iteration $(i), set scale to maximum value: $(sigold)",
                    )
                else
                    error("linesearch failed at iteration $(i) with beta0 = $(p.beta0)")
                end
            end
            # Update μ and compute deviance with new f. Do not recompute ∇β
            sig = scale(
                setη!(m; updatescale=true, verbose=verbose, sigma0=sigold, fallback=maxσ),
            )
        end
        installbeta!(p, f)
        r.σ = sig

        # Test for convergence
        Δsig = (sigold - sig)
        verbose && println("Iteration: $i, scale: $sig, Δsig: $(Δsig)")
        tol = max(rtol * sigold, atol)
        if -tol < Δsig < tol || sig < atol
            cvg = true
            break
        end
        @assert isfinite(sig) && !iszero(sig)
        sigold = sig
    end
    cvg || throw(ConvergenceException(maxiter))
    m
end


"""
    pirls_τestimate!(m::RobustLinearModel{T}; verbose::Bool=false, maxiter::Integer=30,
           minstepfac::Real=1e-3, atol::Real=1e-6, rtol::Real=1e-6,
           beta0::AbstractVector=T[], sigma0::Union{Nothing, T}=nothing)

(Penalized) Iteratively Reweighted Least Square procedure for τ-estimation.
The Penalized aspect is not implemented (yet).
"""
function pirls_τestimate!(
    m::RobustLinearModel{T};
    verbose::Bool=false,
    maxiter::Integer=30,
    minstepfac::Real=1e-3,
    atol::Real=1e-6,
    rtol::Real=1e-5,
    miniter::Int=2,
    beta0::AbstractVector=[],
    sigma0::Union{Nothing,T}=nothing,
) where {T<:AbstractFloat}

    # Check arguments
    maxiter >= 1 || throw(ArgumentError("maxiter must be positive"))
    0 < minstepfac < 1 || throw(ArgumentError("minstepfac must be in (0, 1)"))

    # Extract fields and set convergence flag
    cvg, p, r = false, m.pred, m.resp

    ## Initialize σ, default to largest value
    maxσ = -(-(extrema(r.y)...)) / 2
    if !isnothing(sigma0)
        r.σ = sigma0
    else
        r.σ = maxσ
    end

    ## Initialize β or set it to the provided values
    setβ0!(m, beta0)

    # Initialize μ and compute residuals
    setinitη!(m)

    # Compute initial τ-scale
    tauold = tauscale(setη!(m; updatescale=true); verbose=verbose)
    installbeta!(p, 1)

    verbose && println("initial τ-scale: $(@sprintf("%.4g", tauold))")
    for i in 1:maxiter
        f = 1.0 # line search factor
        local tau

        # Compute the change to β, update μ and compute deviance
        tau = tauscale(
            setη!(m; updatescale=true, verbose=verbose, fallback=maxσ);
            verbose=verbose,
        )

        # Assert the deviance is positive (up to rounding error)
        @assert tau > -atol

        verbose && println(
            "scale at step $i: $(@sprintf("%.4g", tau)), crit=$((tauold - tau)/tauold)",
        )

        # Line search
        ## If the scale isn't declining then half the step size
        ## The rtol*abs(sigold) term is to avoid failure when scale
        ## is unchanged except for rounding errors.
        while tau > tauold + rtol * tau
            f /= 2
            if f <= minstepfac
                if i <= miniter
                    tauold = maxσ
                    r.σ = tauold
                    verbose && println(
                        "linesearch failed at early iteration $(i), set scale to maximum value: $(tauold)",
                    )
                else
                    error("linesearch failed at iteration $(i) with beta0 = $(p.beta0)")
                end
            end

            # Update μ and compute deviance with new f. Do not recompute ∇β
            tau = tauscale(setη!(m; updatescale=true))
        end
        installbeta!(p, f)

        # Test for convergence
        Δtau = (tauold - tau)
        verbose && println("Iteration: $i, scale: $tau, Δsig: $(Δtau)")
        tol = max(rtol * tauold, atol)
        if -tol < Δtau < tol || tau < atol
            cvg = true
            break
        end
        @assert isfinite(tau) && !iszero(tau)
        tauold = tau
    end
    cvg || throw(ConvergenceException(maxiter))
    m
end



##########
###   Resampling
##########

"""
For S- and τ-Estimators, compute the minimum number of subsamples to draw
to ensure that with probability 1-α, at least one of the subsample
is free of outlier, given that the ratio of outlier/clean data is ε.
The number of data point per subsample is p, that should be at least
equal to the degree of freedom.
"""
function resampling_minN(p::Int, α::Real=0.05, ε::Real=0.5)
    ceil(Int, abs(log(α) / log(1 - (1 - ε)^p)))
end


function resampling_initialcoef(m, inds)
    # Get the subsampled model matrix, response and weights
    Xi = modelmatrix(m)[inds, :]
    yi = response(m)[inds]
    wi = Vector(weights(m)[inds])

    # Fit with OLS
    coef(lm(Xi, yi; wts=wi))
end

"""
    best_from_resampling(m::RobustLinearModel, ::Type{E}; kwargs...) where {E<:Union{SEstimator, MMEstimator, TauEstimator}}

Return the best scale σ0 and coefficients β0 from resampling of the S- or τ-Estimate.
"""
function resampling_best_estimate(
    m::RobustLinearModel,
    ::Type{E};
    propoutliers::Real=0.5,
    Nsamples::Union{Nothing,Int}=nothing,
    Nsubsamples::Int=10,
    Npoints::Union{Nothing,Int}=nothing,
    Nsteps_β::Int=2,
    Nsteps_σ::Int=1,
    verbose::Bool=false,
    rng::AbstractRNG=GLOBAL_RNG,
) where {E<:Union{SEstimator,MMEstimator,TauEstimator}}

    ## TODO: implement something similar to DetS (not sure it could apply)
    ## Hubert2015 - The DetS and DetMM estimators for multivariate location and scatter
    ## (https://www.sciencedirect.com/science/article/abs/pii/S0167947314002175)

    if isnothing(Nsamples)
        Nsamples = resampling_minN(dof(m), 0.05, propoutliers)
    end
    if isnothing(Npoints)
        Npoints = dof(m)
    end
    Nsubsamples = min(Nsubsamples, Nsamples)


    verbose && println("Start $(Nsamples) subsamples...")
    σis = zeros(Nsamples)
    βis = zeros(dof(m), Nsamples)
    for i in 1:Nsamples
        # TODO: to parallelize, make a deepcopy of m
        inds = sample(rng, 1:nobs(m), Npoints; replace=false, ordered=false)
        # Find OLS fit of the subsample
        βi = resampling_initialcoef(m, inds)
        verbose && println("Sample $(i)/$(Nsamples): β0 = $(βi)")

        ## Initialize β or set it to the provided values
        setβ0!(m, βi)
        # Initialize μ and compute residuals
        setinitη!(m)
        # Initialize σ as mad(residuals)
        setinitσ!(m)

        σi = 0
        for k in 1:Nsteps_β
            setη!(
                m;
                updatescale=true,
                verbose=verbose,
                sigma0=:mad,
                nmax=Nsteps_σ,
                approx=true,
            )

            σi = if E <: TauEstimator
                tauscale(m)
            else # if E <: Union{SEstimator, MMEstimator}
                scale(m)
            end
            installbeta!(m.pred, 1)
        end
        σis[i] = σi
        βis[:, i] .= coef(m)
        verbose && println("Sample $(i)/$(Nsamples): β1=$(βis[:, i])\tσ1=$(σi)")
    end

    verbose && println("Sorted scales: $(sort(σis))")
    inds = sortperm(σis)[1:Nsubsamples]
    σls = σis[inds]
    βls = βis[:, inds]

    verbose && println("Keep best $(Nsubsamples) subsamples: $(inds)")
    for l in 1:Nsubsamples
        σl, βl = σls[l], βls[:, l]
        # TODO: to parallelize, make a deepcopy of m

        if E <: Union{SEstimator,MMEstimator}
            try
                pirls_Sestimate!(m; verbose=verbose, beta0=βl, sigma0=σl, miniter=3)
                σls[l] = scale(m)
            catch e
                # Didn't converge, set to infinite scale
                σls[l] = Inf
            end
        elseif E <: TauEstimator
            try
                pirls_τestimate!(m; verbose=verbose, beta0=βl, sigma0=σl)
                σls[l] = tauscale(m)
            catch e
                # Didn't converge, set to infinite scale
                σls[l] = Inf
            end
        else
            error("estimator $E not supported.")
        end
        # Update coefficients
        βls[:, l] .= coef(m)

        verbose && println("Subsample $(l)/$(Nsubsamples): β2=$(βls[:, l])\tσ2=$(σls[l])")
    end
    N = argmin(σls)
    ## TODO: for τ-Estimate, the returned scale is τ not σ
    verbose && println("Best subsample: β=$(βls[:, N])\tσ=$(σls[N])")
    return σls[N], βls[:, N]
end
