push!(LOAD_PATH, "./src")
push!(LOAD_PATH, "./EntropyStableEuler")

# "Packages"
using Revise # reduce recompilation
using Plots
using Documenter
using LinearAlgebra
using SparseArrays
using Profile

# "User defined modules"
using Utils
using Basis1D
using Basis2DQuad
using UniformQuadMesh

using EntropyStableEuler

"Approximation parameters"
N = 3 # The order of approximation
K1D = 8

"Mesh related variables"
Kx = 2*K1D
Ky = K1D
(VX, VY, EToV) = uniform_quad_mesh(Kx, Ky)
VX = @. 20*(1+VX)/2
VY = @. 5*VY

Nfaces = 4  # number of faces per element
K  = size(EToV, 1); # The number of element on the mesh we constructed
Nv = size(VX, 1); # Total number of nodes on the mesh
EToE, EToF = connect_mesh(EToV,quad_face_vertices())

"Set up reference element nodes and operators"
r, s = nodes_2D(N)
V = vandermonde_2D(N, r, s)
Vr, Vs = grad_vandermonde_2D(N, r, s)
Dr = Vr / V
Ds = Vs / V

"Quadrature operators"
rq,sq,wq = quad_nodes_2D(N)
Vq = vandermonde_2D(N,rq,sq)/V
M = transpose(Vq)*diagm(wq)*Vq
Pq = M\(transpose(Vq)*diagm(wq))

"Reference face nodes and normals"
# r1D = gauss_lobatto_quad(0,0,N)
# V1D = vandermonde_1D(N,r1D) # hack together face quad nodes
# w1D = vec(sum(inv(V1D*transpose(V1D)),dims=2))
r1D,w1D = gauss_quad(0,0,N)
e = ones(size(r1D))
z = zeros(size(r1D))
rf = [r1D; e; -r1D; -e]
sf = [-e; r1D; e; -r1D]
wf = vec(repeat(w1D,Nfaces,1));
nrJ = [z; e; z; -e]
nsJ = [-e; z; e; z]
Vf = vandermonde_2D(N,rf,sf)/V

"Make hybridized SBP operators"
Qr = Pq'*M*Dr*Pq
Qs = Pq'*M*Ds*Pq
Ef = Vf*Pq
Br = diagm(wf.*nrJ)
Bs = diagm(wf.*nsJ)
Qrh = .5*[Qr-Qr' Ef'*Br;
-Br*Ef Br]
Qsh = .5*[Qs-Qs' Ef'*Bs;
-Bs*Ef Bs]

"Lift matrix"
Lf = M\(transpose(Vf)*diagm(wf))

"interpolation to and from hybridized quad points"
Vh = [Vq; Vf]
Ph = M\transpose(Vh)

"sparse skew symmetric versions of the operators"
Qrhskew = .5*(Qrh-transpose(Qrh))
Qshskew = .5*(Qsh-transpose(Qsh))
Qrhskew = droptol!(sparse(Qrhskew),1e-12)
Qshskew = droptol!(sparse(Qshskew),1e-12)
Vh = droptol!(sparse(Vh),1e-12)
Ph = droptol!(sparse(Ph),1e-12)
Lf = droptol!(sparse(Lf),1e-12)

"Map to physical nodes"
r1,s1 = nodes_2D(1)
V1 = vandermonde_2D(1,r,s)/vandermonde_2D(1,r1,s1)
x = V1*VX[transpose(EToV)]
y = V1*VY[transpose(EToV)]

"Face nodes and connectivity maps"
xf = Vf*x
yf = Vf*y
mapM, mapP, mapB = build_node_maps(xf, yf, Nfaces, EToE, EToF)

"Make node maps periodic"
LX = maximum(VX)-minimum(VX)
LY = maximum(VY)-minimum(VY)
mapPB = build_periodic_boundary_maps(xf,yf,LX,LY,Nfaces,mapM,mapP,mapB)
mapP[mapB] = mapPB

"Geometric factors and surface normals"
rxJ, sxJ, ryJ, syJ, J = geometric_factors(x, y, Dr, Ds)
nxJ = (Vf*rxJ).*nrJ + (Vf*sxJ).*nsJ;
nyJ = (Vf*ryJ).*nrJ + (Vf*syJ).*nsJ;
sJ = @. sqrt(nxJ^2 + nyJ^2)

"Hybridized geofacs"
rxJh = Vh*rxJ; sxJh = Vh*sxJ
ryJh = Vh*ryJ; syJh = Vh*syJ

"initial conditions"
γ = 1.4
rho,u,v,p = vortex(x,y,0)
rhou = @. rho*u
rhov = @. rho*v
E = @. p/(γ-1) + .5*rho*(u^2+v^2)
Q = (rho,rhou,rhov,E)

"convert to Gauss node basis"
Vh = droptol!(sparse([diagm(ones(length(rq))); Ef]),1e-12)
Ph = droptol!(sparse(diagm(@. 1/wq)*transpose(Vh)),1e-12)
Lf = droptol!(sparse(diagm(@. 1/wq)*(transpose(Ef)*diagm(wf))),1e-12)
Q = collect(Vq*Q[i] for i in eachindex(Q)) # interp to quad pts

"Pack arguments into tuples"
ops = (Qrhskew,Qshskew,Ph,Lf)
geo = (rxJh,sxJh,ryJh,syJh,J,nxJ,nyJ,sJ)
Nfp = length(r1D)
mapM = reshape(mapM,Nfp*Nfaces,K)
mapP = reshape(mapP,Nfp*Nfaces,K)
nodemaps = (mapP,mapB)

"Time integration"
rk4a = [            0.0 ...
-567301805773.0/1357537059087.0 ...
-2404267990393.0/2016746695238.0 ...
-3550918686646.0/2091501179385.0  ...
-1275806237668.0/842570457699.0];
rk4b = [ 1432997174477.0/9575080441755.0 ...
5161836677717.0/13612068292357.0 ...
1720146321549.0/2090206949498.0  ...
3134564353537.0/4481467310338.0  ...
2277821191437.0/14882151754819.0]
rk4c = [ 0.0  ...
1432997174477.0/9575080441755.0 ...
2526269341429.0/6820363962896.0 ...
2006345519317.0/3224310063776.0 ...
2802321613138.0/2924317926251.0 ...
1.0];

"Estimate timestep"
CN = (N+1)*(N+2)  # estimated trace constant
CFL = .5;
dt = CFL * 2 / (CN*K1D)
T = .5 # endtime
Nsteps = convert(Int,ceil(T/dt))

function rhs(Qh,Uh,ops,geo,nodemaps,flux_fun)

    # unpack args
    (Qrhskew,Qshskew,Ph,Lf)=ops
    (rxJ,sxJ,ryJ,syJ,J,nxJ,nyJ,sJ)=geo
    (mapP,mapB) = nodemaps
    Nh = size(Qrhskew,1)
    Nq = size(Ph,1)
    K  = size(J,2)

    QM = [Qh[fld][Nq+1:end,:] for fld in eachindex(Qh)]
    QP = [QM[fld][mapP] for fld in eachindex(QM)]

    # lax friedrichs dissipation
    UM = [Uh[fld][Nq+1:end,:] for fld in eachindex(Uh)]
    UP = [UM[fld][mapP] for fld in eachindex(UM)]
    lam = abs.(wavespeed(UM))
    LFc = .5*max.(lam,lam[mapP]).*sJ
    # LFc = 0.0

    fSx,fSy = flux_fun(QM,QP)
    flux = [fSx[fld].*nxJ + fSy[fld].*nyJ - LFc.*(UP[fld]-UM[fld]) for fld in eachindex(fSx)]
    rhsQ = [Lf*flux[fld] for fld in eachindex(flux)]

    # compute volume contributions
    for e = 1:K
        (rho,u,v,beta) = [Qh[fld][:,e] for fld in eachindex(Qh)]
        rhox,rhoy   = meshgrid(rho)
        ux,uy       = meshgrid(u)
        vx,vy       = meshgrid(v)
        betax,betay = meshgrid(beta)

        Ux = (rhox,ux,vx,betax)
        Uy = (rhoy,uy,vy,betay)
        Fx,Fy = flux_fun(Ux,Uy)

        Qx = rxJ[1,e]*Qrhskew + sxJ[1,e]*Qshskew
        Qy = ryJ[1,e]*Qrhskew + syJ[1,e]*Qshskew

        for fld in eachindex(Qh)
            rhsQ[fld][:,e] += 2*Ph*sum(Qx.*Fx[fld] + Qy.*Fy[fld],dims=2)
        end
    end

    return [-rhsQ[fld]./J for fld in eachindex(rhsQ)]
end

wJq = diagm(wq)*J
resQ = [zeros(size(x)) for i in eachindex(Q)]

for i = 1:Nsteps

    global Q,resQ,rhstest # for scope, variables are updated

    for INTRK = 1:5

        # interp entropy vars
        VU = v_ufun(Q...)
        Uh = u_vfun([Vh*VU[i] for i in eachindex(VU)]...)

        # convert to rho,u,v,beta vars
        (rho,rhou,rhov,E) = Uh
        u = rhou./rho
        v = rhov./rho
        beta = betafun.(rho,u,v,E)
        Qh = (rho,u,v,beta) # redefine Q

        rhsQ = rhs(Qh,Uh,ops,geo,nodemaps,euler_fluxes)

        if INTRK==5
            rhstest = sum([sum(wJq.*VU[fld].*rhsQ[fld]) for fld in eachindex(VU)])
        end

        # rhsQ = [zeros(size(x)) for i in eachindex(Q)]
        resQ = @. rk4a[INTRK]*resQ + dt*rhsQ
        Q = @. Q + rk4b[INTRK]*resQ
    end

    if i%10==0 || i==Nsteps
        println("Time step: ", i, " out of ", Nsteps, ", rhstest = ",rhstest)
    end
end

# funs = (v_ufun,u_vfun,betafun,euler_fluxes)
# Q = rk_run(Q,rhs,funs)
#
(rho,rhou,rhov,E) = [Pq*Q[fld] for fld in eachindex(Q)]

"plotting nodes"
rp, sp = equi_nodes_2D(15)
Vp = vandermonde_2D(N,rp,sp)/V

# pyplot(size=(200,200),legend=false,markerstrokewidth=0,markersize=2)
gr(size=(300,300),legend=false,markerstrokewidth=0,markersize=2,aspect_ratio=:equal)

vv = Vp*rho
scatter(Vp*x,Vp*y,vv,zcolor=vv,camera=(0,90))