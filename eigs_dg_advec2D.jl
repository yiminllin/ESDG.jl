using Revise # reduce need for recompile
using Plots
using LinearAlgebra

push!(LOAD_PATH, "./src") # user defined modules
using CommonUtils
using Basis1D
using Basis2DTri
using UniformTriMesh

"Define approximation parameters"
N   = 2 # The order of approximation
K1D = 4 # number of elements along each edge of a rectangle

"Define mesh and compute connectivity
- (VX,VY) are and EToV is a connectivity matrix
- connect_mesh computes a vector FToF such that face i is connected to face j=FToF[i]"
VX,VY,EToV = uniform_tri_mesh(K1D,K1D)
FToF = connect_mesh(EToV,tri_face_vertices())
Nfaces,K = size(FToF)

"Construct matrices on reference elements
- r,s are vectors of interpolation nodes
- V is the matrix arising in polynomial interpolation, e.g. solving V*u = [f(x_1),...,f(x_Np)]
- inv(V) transforms from a nodal basis to an orthonormal basis.
- If Vr evaluates derivatives of the orthonormal basis at nodal points
- then, Vr*inv(V) = Vr/V transforms nodal values to orthonormal coefficients, then differentiates the orthonormal basis"
r, s = nodes_2D(N)
V = vandermonde_2D(N, r, s)
Vr, Vs = grad_vandermonde_2D(N, r, s)
invM = (V*V')
Dr = Vr/V
Ds = Vs/V

"Nodes on faces, and face node coordinate
- r1D,w1D are quadrature nodes and weights
- rf,sf = mapping 1D quad nodes to the faces of a triangle"
r1D, w1D = gauss_quad(0,0,N)
Nfp = length(r1D) # number of points per face
e = ones(Nfp,1) # vector of all ones
z = zeros(Nfp,1) # vector of all zeros
rf = [r1D; -r1D; -e];
sf = [-e; r1D; -r1D];
wf = vec(repeat(w1D,3,1));
Vf = vandermonde_2D(N,rf,sf)/V # interpolates from nodes to face nodes
LIFT = invM*(transpose(Vf)*diagm(wf)) # lift matrix used in rhs evaluation

"Construct global coordinates
- vx = VX[EToV'] = a 3xK matrix of vertex values for each element
- V1*vx uses the linear polynomial defined by 3 vertex values to
interpolate nodal points on the reference element to physical elements"
r1,s1 = nodes_2D(1)
V1 = vandermonde_2D(1,r,s)/vandermonde_2D(1,r1,s1)
x = V1*VX[transpose(EToV)]
y = V1*VY[transpose(EToV)]

"Compute connectivity maps: uP = exterior value used in DG numerical fluxes"
xf,yf = (x->Vf*x).((x,y))
mapM,mapP,mapB = build_node_maps((xf,yf),FToF)
mapM = reshape(mapM,Nfp*Nfaces,K)
mapP = reshape(mapP,Nfp*Nfaces,K)

"Make boundary maps periodic"
LX,LY = (x->maximum(x)-minimum(x)).((VX,VY)) # find lengths of domain
mapPB = build_periodic_boundary_maps(xf,yf,LX,LY,Nfaces*K,mapM,mapP,mapB)
mapP[mapB] = mapPB

"Compute geometric factors and surface normals"
rxJ, sxJ, ryJ, syJ, J = geometric_factors(x, y, Dr, Ds)

"nhat = (nrJ,nsJ) are reference normals scaled by edge length
- physical normals are computed via G*nhat, G = matrix of geometric terms
- sJ is the normalization factor for (nx,ny) to be unit vectors"
nrJ = [z; e; -e]
nsJ = [-e; e; z]
nxJ = (Vf*rxJ).*nrJ + (Vf*sxJ).*nsJ;
nyJ = (Vf*ryJ).*nrJ + (Vf*syJ).*nsJ;
sJ = @. sqrt(nxJ^2 + nyJ^2)

"pack arguments into tuples"
ops = (Dr,Ds,LIFT,Vf)
vgeo = (rxJ,sxJ,ryJ,syJ,J)
fgeo = (nxJ,nyJ,sJ)
mapP = reshape(mapP,Nfp*Nfaces,K)
nodemaps = (mapP,mapB)

"Define function to evaluate the RHS"
function rhs(u,ops,vgeo,fgeo,nodemaps)
    # unpack arguments
    Dr,Ds,LIFT,Vf = ops
    rxJ,sxJ,ryJ,syJ,J = vgeo
    nxJ,nyJ,sJ = fgeo
    (mapP,mapB) = nodemaps

    uM = Vf*u # interpolate solution to face nodes
    uP = uM[mapP]
    tau = 1
    flux = @. nxJ*(.5*(uP-uM)) - .5*tau*(uP-uM).*abs(nxJ)
    # flux = @. nxJ*(.5*(uP-uM)) - .5*tau*(uP-uM)

    ur = Dr*u
    us = Ds*u
    ux = @. rxJ*ur + sxJ*us;
    rhsu = ux + LIFT*flux

    return -rhsu./J
end

u = zeros(size(x))
A = zeros(length(u),length(u))
for i = 1:length(u)
    u[i] = 1
    rhsi = rhs(u,ops,vgeo,fgeo,nodemaps)
    A[:,i] = (x->x[:])(rhsi)
    u[i] = 0
end

lam = eigvals(A)

gr(size=(300,300),legend=false,
markerstrokewidth=2,markersize=8)
scatter!(lam)
