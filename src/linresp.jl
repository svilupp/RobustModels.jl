


function show(io::IO, obj::ConvergenceFailed)
    println(io, "failed to find a solution: $(obj.reason)")
end


"""
    RobustLinResp

Robust linear response structure.

Solve the following minimization problem:

```math
\\min \\sum_i \\rho\\left(\\dfrac{r_i}{\\hat{\\sigma}}\right)
```

# Fields

- `est`: estimator used for the model
- `y`: response vector
- `μ`: mean response vector
- `offset`: offset added to `Xβ` to form `μ`. Can be of length 0
- `wts`: prior case weights.  Can be of length 0.
- `σ`: current estimate of the scale or dispersion
- `devresid`: the deviance residuals
- `wrkwt`: working case weights for the Iteratively Reweighted Least Squares (IRLS) algorithm
- `wrkres`: working residuals for IRLS
- `wrkscaledres`: scaled residuals for IRLS

"""
mutable struct RobustLinResp{T<:AbstractFloat,V<:AbstractVector{T},M<:AbstractEstimator} <:
               RobustResp{T}
    "`est`: estimator used for the model"
    est::M
    "`y`: response vector"
    y::V
    "`μ`: mean response vector"
    μ::V
    "`offset`: offset added to `Xβ` to form `μ`. Can be of length 0"
    offset::V
    "`wts`: prior case weights.  Can be of length 0."
    wts::V
    "`σ`: current estimate of the scale or dispersion"
    σ::T
    "`devresid`: the deviance residuals"
    devresid::V
    "`wrkwt`: working case weights for the Iteratively Reweighted Least Squares (IRLS) algorithm"
    wrkwt::V
    "`wrkres`: working residuals for IRLS"
    wrkres::V
    "`wrkscaledres`: scaled residuals for IRLS"
    wrkscaledres::V

    function RobustLinResp{T,V,M}(
        est::M,
        y::V,
        μ::V,
        off::V,
        wts::V,
        σ::Real=1,
    ) where {V<:AbstractVector{T},M<:AbstractEstimator} where {T<:AbstractFloat}
        n = length(y)
        length(μ) == n ||
            throw(DimensionMismatch("lengths of μ and y are not equal: $(length(μ)!=n)"))
        ll = length(off)
        ll in (0, n) || throw(DimensionMismatch("length of offset is $ll, must be $n or 0"))
        ll = length(wts)
        ll in (0, n) || throw(DimensionMismatch("length of wts is $ll, must be $n or 0"))
        σ > 0 || throw(DomainError(σ, "scale/dispersion must be positive"))
        new{T,V,M}(
            est,
            y,
            μ,
            off,
            wts,
            float(σ),
            similar(y),
            similar(y),
            similar(y),
            similar(y),
        )
    end
end

"""
    RobustLinResp(est::M, y::V, off::V, wts::V, σ::Real=1)
            where {V<:FPVector, M<:AbstractEstimator}

Create a response structure by copying the value of `y` to the mean `μ`.

"""
function RobustLinResp(
    est::M,
    y::V,
    off::V,
    wts::V,
    σ::Real=1,
) where {V<:FPVector,M<:AbstractEstimator}
    r = RobustLinResp{eltype(y),V,M}(est, y, similar(y), off, wts, float(σ))
    initresp!(r)
    return r
end

"""
    RobustLinResp(est::M, y, off, wts) where {M<:AbstractEstimator}

Convert the arguments to float arrays
"""
function RobustLinResp(est::M, y, off, wts) where {M<:AbstractEstimator}
    RobustLinResp(
        est,
        float(collect(y)),
        float(collect(off)),
        float(collect(wts)),
        float(1),
    )
end


function initresp!(r::RobustResp{T}) where {T}
    # Set μ to 0
    fill!(r.μ, 0)

    # Reset the factor of the TauEstimator
    if isa(r.est, TauEstimator)
        update_weight!(r.est, 0)
    end

    # Set residual (without offset)
    broadcast!(-, r.wrkres, r.y, r.μ)

    # Set working weights to the data weights
    if !isempty(r.wts)
        copyto!(r.wrkwt, r.wts)
    else
        fill!(r.wrkwt, 1)
    end
end


function Base.getproperty(r::RobustLinResp, s::Symbol)
    if s ∈ (:mu, :η, :eta)
        r.μ
    elseif s ∈ (:sigma, :scale)
        r.σ
    else
        getfield(r, s)
    end
end

function dispersion(
    r::RobustResp,
    dof_residual::Real=(nobs(r) - 1),
    sqr::Bool=false,
    robust::Bool=true,
)
    wrkwt, wrkres, wrkscaledres = r.wrkwt, r.wrkres, r.wrkscaledres
    if robust
        s = (r.σ)^2 *
            sum(i -> wrkwt[i] * abs2(wrkscaledres[i]), eachindex(wrkwt, wrkres)) /
            dof_residual
    else
        s = sum(i -> wrkwt[i] * abs2(wrkres[i]), eachindex(wrkwt, wrkres)) / dof_residual
    end

    return sqr ? s : sqrt(s)
end


"""
    location_variance(r::RobustLinResp, sqr::Bool=false)

Compute the part of the variance of the coefficients `β` that is due to the encertainty
from the location. If `sqr` is `false`, return the standard deviation instead.

From Maronna et al., Robust Statistics: Theory and Methods, Equation 4.49
"""
function location_variance(
    r::RobustLinResp,
    dof_residual::Real=(nobs(r) - 1),
    sqr::Bool=false,
)
    lpsi(x) = psi(r.est, x)
    lpsider(x) = psider(r.est, x)

    if isa(r.est, UnionL1)
        @warn "coefficient variance is not well defined for L1Estimator."
        return Inf
    end

    v = if isempty(r.wts)
        v = mean((lpsi.(r.wrkscaledres)) .^ 2)
        v /= (mean(lpsider.(r.wrkscaledres)))^2
    else
        wts = weights(r.wts)
        v = mean((lpsi.(r.wrkscaledres)) .^ 2, wts)
        v /= (mean(lpsider.(r.wrkscaledres), wts))^2
    end
    v *= r.σ^2
    v *= (nobs(r) / dof_residual)

    return sqr ? v : sqrt(v)
end

deviance(r::RobustResp) = sum(r.devresid)

function nulldeviance(r::RobustResp; intercept::Bool=true)
    ## TODO: take wts into account
    y, σ = r.y, r.σ
    μi = intercept ? mean(y) : zero(eltype(y))

    dev = 0
    @inbounds for i in eachindex(y)
        dev += 2 * rho(r.est, (y[i] - μi) / σ)
    end
    dev
end

## TODO: define correctly the loglikelihood of the full model
fullloglikelihood(r::RobustLinResp) = -log(r.scale) - log(estimator_norm(r.est))

loglikelihood(r::RobustResp) = fullloglikelihood(r) - deviance(r) / 2

function nullloglikelihood(r::RobustResp; intercept::Bool=true)
    return fullloglikelihood(r) - nulldeviance(r; intercept=intercept) / 2
end

response(r::RobustResp) = r.y

Estimator(r::RobustResp) = r.est

function weights(r::RobustResp{T}) where {T<:AbstractFloat}
    if isempty(r.wts)
        weights(ones(T, length(r.y)))
    else
        weights(r.wts)
    end
end

fitted(r::RobustLinResp) = r.μ

residuals(r::RobustLinResp) = r.wrkres

workingweights(r::RobustLinResp) = r.wrkwt

"""
    nobs(obj::RobustResp)
For linear and generalized linear models, returns the number of elements of the response
"""
function nobs(r::RobustResp{T}) where {T}
    if !isempty(r.wts)
        ## Suppose that the weights are probability weights
        count(!iszero, r.wts)
        # convert(T, sum(r.wts))
    else
        size(r.y, 1)
    end
end

function applyoffset!(r::RobustLinResp)
    # Subtract the offset because it will be added in the updateres! step
    if size(r.offset, 1) == size(r.y, 1)
        @inbounds @simd for i in eachindex(r.μ, r.offset)
            r.μ[i] -= r.offset[i]
        end
    end
end

"""
    setμ!{T<:FPVector}(r::RobustResp{T}, μ::T)
Update the mean to the given value `μ`.
If no value is provided, μ is set to the mean response `mean(r.y)`.
"""
function setμ! end

function setμ!(r::RobustLinResp, μ::T) where {T<:Real}
    fill!(r.μ, μ)

    # Subtract the offset because it will be added in the updateres! step
    applyoffset!(r)
end

function setμ!(r::RobustLinResp, μ::V) where {V<:FPVector}
    copyto!(r.μ, μ)

    # Subtract the offset because it will be added in the updateres! step
    applyoffset!(r)
end

function setμ!(r::RobustLinResp)
    if !isempty(r.wts)
        # Weighted mean
        m = mean(r.y, weights(r.wts))
    else
        m = mean(r.y)
    end
    setμ!(r, m)
end


function updateres!(r::RobustLinResp; updatescale=true, kwargs...)
    if updatescale
        _updateres_and_scale!(r; kwargs...)
    else
        _updateres!(r)
    end
end

"""
    _updateres!{T<:FPVector}(r::RobustResp{T})
Update the mean, working weights, working residuals and deviance residuals,
of the response `r`. The loss function for location estimation is used.
"""
function _updateres!(
    r::RobustLinResp{T,V,M},
) where {T<:AbstractFloat,V<:FPVector,M<:AbstractEstimator}
    ## Add offset to the linear predictor, if offset is defined
    ## and copy the linear predictor to the mean
    if length(r.offset) != 0
        broadcast!(+, r.μ, r.μ, r.offset)
    end

    y, μ, σ, devresid = r.y, r.μ, r.σ, r.devresid
    wrkres, wrkscaledres, wrkwt = r.wrkres, r.wrkscaledres, r.wrkwt

    invσ = inv(σ) # reduce #allocations using * instead of /.
    @inbounds for i in eachindex(y, μ, wrkres, wrkscaledres, wrkwt, devresid)
        wrkscaledres[i] = wrkres[i] = y[i] - μ[i]
        wrkscaledres[i] *= invσ
        wrkwt[i] = weight(r.est, wrkscaledres[i])
        devresid[i] = 2 * rho(r.est, wrkscaledres[i])
    end

    ## Multiply by the observation weights
    if !isempty(r.wts)
        broadcast!(*, r.devresid, r.devresid, r.wts)
        broadcast!(*, r.wrkwt, r.wrkwt, r.wts)
    end
end


function _updateres_and_scale!(
    r::RobustLinResp{T,V,M};
    kwargs...,
) where {T<:AbstractFloat,V<:FPVector,M<:Union{SEstimator,MMEstimator}}
    ## Add offset to the linear predictor, if offset is defined
    ## and copy the linear predictor to the mean
    if length(r.offset) != 0
        broadcast!(+, r.μ, r.μ, r.offset)
    end

    y, μ, devresid = r.y, r.μ, r.devresid
    wrkres, wrkscaledres, wrkwt = r.wrkres, r.wrkscaledres, r.wrkwt

    # First pass, compute the residuals
    @inbounds for i in eachindex(y, μ, wrkres)
        wrkres[i] = y[i] - μ[i]
    end

    # Second pass, compute the scale
    updatescale!(r; kwargs...)

    # Third pass, compute the scaled residuals, weights and deviance residuals
    invσ = inv(r.σ) # reduce #allocations using * instead of /.
    @inbounds for i in eachindex(wrkres, wrkscaledres, wrkwt, devresid)
        wrkscaledres[i] = wrkres[i] * invσ
        wrkwt[i] = weight(r.est, wrkscaledres[i])
        devresid[i] = 2 * rho(r.est, wrkscaledres[i])
    end

    ## Multiply by the observation weights
    if !isempty(r.wts)
        broadcast!(*, r.devresid, r.devresid, r.wts)
        broadcast!(*, r.wrkwt, r.wrkwt, r.wts)
    end
end


function _updateres_and_scale!(
    r::RobustLinResp{T,V,M};
    kwargs...,
) where {T<:AbstractFloat,V<:FPVector,M<:TauEstimator}
    ## Add offset to the linear predictor, if offset is defined
    ## and copy the linear predictor to the mean
    if length(r.offset) != 0
        broadcast!(+, r.μ, r.μ, r.offset)
    end

    y, μ, devresid = r.y, r.μ, r.devresid
    wrkres, wrkscaledres, wrkwt = r.wrkres, r.wrkscaledres, r.wrkwt

    # First pass, compute the residuals
    @inbounds for i in eachindex(y, μ, wrkres)
        wrkres[i] = y[i] - μ[i]
    end

    # Second pass, compute the scale
    updatescale!(r; kwargs..., sigma0=:mad)

    # Third pass, compute the scaled residuals
    invσ = inv(r.σ) # reduce #allocations using * instead of /.
    @inbounds for i in eachindex(wrkres, wrkscaledres)
        wrkscaledres[i] = wrkres[i] * invσ
    end

    # Fourth pass, compute the weights of the τ-estimator
    update_weight!(r.est, wrkscaledres; wts=r.wts)

    # Fifth pass, compute the weights and deviance residuals
    @inbounds for i in eachindex(wrkscaledres, wrkwt, devresid)
        wrkwt[i] = weight(r.est, wrkscaledres[i])
        devresid[i] = 2 * rho(r.est, wrkscaledres[i])
    end

    ## Multiply by the observation weights
    if !isempty(r.wts)
        broadcast!(*, r.devresid, r.devresid, r.wts)
        broadcast!(*, r.wrkwt, r.wrkwt, r.wts)
    end
end

"""
    updatescale!(
        r::RobustLinResp;
        sigma0::Union{Symbol,AbstractFloat}=r.σ,
        fallback::Union{Nothing, AbstractFloat}=nothing,
        verbose::Bool=false,
        kwargs...
    )

Compute the M-scale estimate from the estimator and residuals.
`sigma0` : initial value of the scale (default to r.σ),
           or `:mad` if it is estimated from mad(res).
`fallback` : if the algorithm does not converge, return the fallback value.
             If nothing, raise a ConvergenceFailed error.
`kwargs` : keyword arguments for the scale_estimate function.
"""
function updatescale!(
    r::RobustLinResp;
    sigma0::Union{Symbol,AbstractFloat}=r.σ,
    fallback::Union{Nothing,AbstractFloat}=nothing,
    verbose::Bool=false,
    kwargs...,
)
    est, res = r.est, r.wrkres
    σ0 = isa(sigma0, AbstractFloat) ? sigma0 : madresidualscale(r)

    if !isbounded(est)
        @warn "scale/dispersion is not changed because the estimator ($(est)) does not"*
              " allow scale estimation, a bounded estimator should be used, like Tukey."
        return r
    end

    verbose && print("Update scale: $(σ0) ")
    σ = try
        scale_estimate(est, res; σ0=σ0, wts=r.wts, kwargs...)
    catch e
        if isa(e, ConvergenceFailed) && !isnothing(fallback)
            verbose && print("  x>  fallback")
            σ = fallback
        else
            verbose && println("  x>  error")
            rethrow(e)
        end
    end
    verbose && println("  ->  $(σ)")
    r.σ = σ
    r
end

scale(r::RobustLinResp, sqr::Bool=false) =
    if sqr
        (r.σ)^2
    else
        r.σ
    end

function tauscale(
    r::RobustLinResp{T,V,M},
    sqr::Bool=false;
    verbose::Bool=false,
    bound::AbstractFloat=0.5,
    sigma0::Union{Symbol,AbstractFloat}=r.σ,
    updatescale::Bool=false,
) where {T,V,M<:TauEstimator}
    # No need to recompute s, as it was called in updateres! and stored in r.σ
    if updatescale
        updatescale!(r; sigma0=sigma0, verbose=verbose)
    end
    tau_scale_estimate(r.est, r.wrkres, r.σ, sqr; wts=r.wts, bound=bound)
end

"""
    madresidualscale(res)

Compute the scale using the MAD of the residuals.
"""
function madresidualscale(
    res::AbstractArray;
    factor::AbstractFloat=1.0,
    wts::AbstractArray=[],
)
    factor > 0 || error("factor should be positive")

    σ = if length(wts) == length(res)
        factor * mad(wts .* abs.(res); normalize=true)
    else
        factor * mad(abs.(res); normalize=true)
    end
    return σ
end
function madresidualscale(r::RobustLinResp; factor::AbstractFloat=1.0)
    madresidualscale(r.wrkres; factor=factor, wts=r.wts)
end

####################
