using Revise # reduce need for recompile
using Plots
using LinearAlgebra

push!(LOAD_PATH, "./src") # user defined modules
using CommonUtils, Basis1D

"Approximation parameters"
K   = 1024 # number of elements
T   = .25  # endtime
CFL = 1   # controls size of timestep

"Grid related variables"
VX = LinRange(-1,1,K+1)
EToV = repeat([0 1],K,1) + repeat(1:K,1,2)
h = diff(VX) # mesh spacing
x = mean(VX[EToV],2) # cell centers

"initial conditions"
u0(x) = @. sin(2*pi*x)
u0(x) = @. exp(-25*(x+.5)^2)
# u0(x) = Float64.(@. abs(x) < .5)
u = u0(x)

"Time integration"
rk4a,rk4b,rk4c = rk45_coeffs()
dt = CFL * minimum(h)
Nsteps = convert(Int,ceil(T/dt))
dt = T/Nsteps

"plotting nodes"
gr(size=(300,300),legend=false,markerstrokewidth=0,markersize=2,linewidth=2)
ulims = (minimum(u)-.5,maximum(u)+.5)
# plt = scatter(x,u,ylims=ulims,title="Timestep 0 out of $Nsteps")

resu = zeros(size(x))
interval = 25
@gif for i = 1:Nsteps
    for INTRK = 1:5
        uL = vcat(u[end],u)
        uR = vcat(u,u[1])

        # conservative version
        tau = @. max(abs(uL),abs(uR)) # local lax-Friedrichs penalization
        flux = @. .5*(uL^2+uR^2)/2 - .5*tau*(uR-uL) # central flux
        rhsu = -diff(flux,dims=1)./h

        # # non-conservative version
        # tau = 1
        # flux = @. .5*(uL+uR) - .5*tau*(uR-uL) # flux for advection
        # rhsu = -u.*diff(flux,dims=1)./h

        @. resu = rk4a[INTRK]*resu + dt*rhsu
        @. u   += rk4b[INTRK]*resu
    end

    if i%interval==0 || i==Nsteps
        println("Number of time steps $i out of $Nsteps")
        scatter(x,u,ylims=ulims)
    end
end every interval

scatter(x,u,ylims=ulims)
