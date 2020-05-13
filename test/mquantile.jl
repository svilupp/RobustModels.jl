using RobustModels
using Test
using RDatasets: dataset
using SparseArrays: SparseMatrixCSC
using StatsModels: @formula, coef
using StatsBase: mad
using GLM: LinearModel

data = dataset("robustbase", "Animals2")
form = @formula(Brain ~ 1 + Body)

λ = mad(data.Brain; normalize=true)
est1 = RobustModels.L2Estimator()
est2 = RobustModels.TukeyEstimator()


@testset "linear: Expectile estimators" begin
    m  = fit(RobustLinearModel, form, data, est1; method=:cg, maxiter=50, verbose=false, initial_scale_estimate=:mad)
    m1 = fit(RobustLinearModel, form, data, est1; quantile=0.5, method=:cg, maxiter=50, verbose=false, initial_scale_estimate=:mad)

    # refit
    # cannot change type to GeneralQuantileEstimator
    @test_throws ErrorException refit!(m; quantile=0.5)

    @testset "$(τ) $(name)" for τ in range(0.1, 0.9, step=0.1), name in ("Expectile", "Quantile")
        println("\n\t\u25CF Estimator: $name($τ)")
        est = getproperty(RobustModels, Symbol(name * "Estimator"))(τ)
        m2 = fit(RobustLinearModel, form, data, est; method=:cg, maxiter=50, initial_scale_estimate=:mad)
        m3 = fit(RobustLinearModel, form, data, est; method=:chol, maxiter=50, initial_scale_estimate=:mad)
        println("rlm(cg)  : ", coef(m2))
        println("rlm(chol): ", coef(m3))
        println(m2)
        if name == "Expectile"
            @test all(isapprox.(coef(m2), coef(m3); rtol=1.0e-5))
            if τ==0.5
                @test all(isapprox.(coef(m), coef(m2); rtol=1.0e-5))
            end

            # refit with new quantile
            refit!(m1; quantile=τ)
            @test all(coef(m1) .== coef(m2))
        elseif name != "Quantile"
            @test all(isapprox.(coef(m2), coef(m3); rtol=1.0e-5))
        end
    end
end


@testset "linear: M-Quantile estimators" begin
    @testset "$(name) estimator" for name in ("Huber", "L1L2", "Fair", "Logcosh", "Arctan") #, "Cauchy", "Geman", "Welsch", "Tukey")
        println("\n\t\u25CF M-Quantile Estimator: $name")
        est = getproperty(RobustModels, Symbol(name * "Estimator"))()
        m1 = fit(RobustLinearModel, form, data, est; method=:cg, maxiter=50, verbose=false, initial_scale_estimate=:mad)
        println("no quant, rlm(cg)  : ", coef(m1))
        @testset "$(τ) quantile" for τ in range(0.1, 0.9, step=0.1)
            m2 = fit(RobustLinearModel, form, data, est; quantile=τ, method=:cg, maxiter=50, verbose=false, initial_scale_estimate=:mad)
            m3 = fit(RobustLinearModel, form, data, est; quantile=τ, method=:chol, maxiter=50, initial_scale_estimate=:mad)
            println("quant $(τ) rlm(cg)  : ", coef(m2))
            println("quant $(τ) rlm(chol): ", coef(m3))
            if τ==0.5
                @test all(isapprox.(coef(m1), coef(m2); rtol=1.0e-5))
            end
            if name != "L1"
                @test all(isapprox.(coef(m2), coef(m3); rtol=1.0e-2))
            end
        end
    end
end
