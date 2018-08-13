#Tensors in Tucker format + functions

export ttensor, randttensor
export coresize, cp_als, display, full, had, hadcten, hosvd, hosvd1, hosvd2, hosvd3, hosvd4, innerprod, isequal, lanczos, lanczos_tridiag, mhadtv, minus, mrank
export msvdvals, mtimes, mttkrp, ndims, nrank, nvecs, permutedims, plus, randrange, randsvd, reorth, reorth!, size, tenmat, ttm, ttv, uminus, norm

"""
    ttensor(cten,fmat)

Tensor in Tucker format defined by its core tensor and factor matrices.
For ttensor X, X.isorth=true if factor matrices are othonormal.
"""
mutable struct ttensor{T<:Number}
	cten::Array{T}
	fmat::MatrixCell
	isorth::Bool
	function ttensor{T}(cten::Array{T},fmat::MatrixCell,isorth::Bool) where T<:Number
		for A in fmat
			if norm(A'*A-eye(size(A,2)))>(size(A,1)^2)*eps()
				isorth=false
			end
		end
		new(cten,fmat,isorth)
	end
end
ttensor(cten::Array{T},fmat::MatrixCell,isorth::Bool) where T=ttensor{T}(cten,fmat,isorth)
ttensor(cten::Array{T},fmat::MatrixCell) where T=ttensor{T}(cten,fmat,true)
ttensor(cten::Array{T},mat::Matrix) where T=ttensor{T}(cten,collect(mat),true)
function ttensor(cten::Array{T},mat...) where T
  fmat=MatrixCell(0)
  for M in mat
			push!(fmat,M)
	end
	ttensor(cten,fmat,true)
end
#If array of matrices isn't defined as MatrixCell, but as M=[M1,M2,...,Mn]:
ttensor(cten::Array{T},fmat::Array{Matrix{T1}},isorth::Bool) where {T,T1<:Number}=ttensor{T}(cten,MatrixCell(fmat),isorth)
ttensor(cten::Array{T},fmat::Array{Matrix{T1}}) where {T,T1<:Number}=ttensor{T}(cten,MatrixCell(fmat),true)

"""
    randttensor(I::Vector,R::Vector)
    randttensor(I::Integer,R::Integer,N::Integer)

Create random ttensor of size I and multilinear rank R, or of order N and size I × ⋯ × I and mulilinear rank (R,...,R).
"""
function randttensorAbstractRange(I::Vector{D},R::Vector{D}) where {D<:Integer}
  @assert(size(I)==size(R),"Size and rank should be of same length.")
  cten=randn(tuple(R...)) #create radnom core tensor
  fmat=Matrix[randn(I[n],R[n]) for n=1:length(I)] #create random factor matrices
  ttensor(cten,fmat)
end
randttensor(I::Integer,R::Integer,N::Integer)=randttensor(repmat([I],N),repmat([R],N));
#For input defined as tuples or nx1 matrices - ranttensor(([I,I,I],[R,R,R]))
function randttensor(arg...)
  randttensor([arg[1]...],[arg[2]...])
end

"""
    coresize(X)

Size of core tensor of a ttensor.
"""
function coresize(X::ttensor{T}) where {T<:Number}
  size(X.cten)
end

#Compute a CP decomposition with R components of a tensor X. **Documentation in tensor.jl.
function cp_als(X::ttensor{T},R::Integer;init="rand",tol=1e-4,maxit=1000,dimorder=[]) where {T<:Number}
    N=ndims(X)
    nr=norm(X)
    K=ktensor
    if length(dimorder) == 0
        dimorder=collect(1:N)
    end
    fmat=MatrixCell(N)
    if isa(init,Vector) || isa(init,MatrixCell)
        @assert(length(init)==N,"Wrong number of initial matrices.")
        for n in dimorder[2:end]
            @assert(size(init[n])==(size(X,n),R),"$(n)-th initial matrix is of wrong size.")
            fmat[n]=init[n]
        end
    elseif init=="rand"
        [fmat[n]=rand(size(X,n),R) for n in dimorder[2:end]]
    elseif init=="eigs" || init=="nvecs"
        [fmat[n]=nvecs(X,n,R) for n in dimorder[2:end]]
    else
        error("Initialization method wrong.")
    end
    G = zeros(R,R,N); #initalize gramians
    [G[:,:,n]=fmat[n]'*fmat[n] for n in dimorder[2:end]]
    fit=0
    for k=1:maxit
        fitold=fit
        lambda=[]
        for n in dimorder
            fmat[n]=mttkrp(X,fmat,n)
            W=reshape(prod(G[:,:,setdiff(collect(1:N),n)],3),Val{2})
            fmat[n]=fmat[n]/W
            if k == 1
                lambda = sqrt.(sum(fmat[n].^2,1))' #2-norm
            else
                lambda = maximum(maximum(abs.(fmat[n]),1),1)' #max-norm
            end
            fmat[n] = fmat[n]./lambda'
            G[:,:,n] = fmat[n]'*fmat[n]
        end
        K=ktensor(vec(lambda),fmat)
        if nr==0
            fit=norm(K)^2-2*innerprod(X,K)
        else
            nr_res=sqrt.(abs.(nr^2+norm(K)^2-2*innerprod(X,K)))
            fir=1-nr_res/nr
        end
        fitchange=abs.(fitold-fit)
        if k>1 && fitchange<tol
            break
        end
    end
    arrange!(K)
    fixsigns!(K)
    K
end

"""
---
TensorToolbox:

    display(X::ttensor[,name])
    display(X::ktensor[,name])
    display(X::htensor[,name])

Displays a tensor X of a given name.
"""
function display(X::ttensor{T},name="ttensor") where {T<:Number}
  print("Tucker tensor of size ",size(X)," with core tensor of size ",coresize(X))
  if X.isorth == true
    print(" with orthonormal factor matrices")
  end
  print(":\n")
  println("$name.cten: ")
  show(STDOUT, "text/plain", X.cten)
  for n=1:ndims(X)
      println("\n\n$name.fmat[$n]:")
      show(STDOUT, "text/plain", X.fmat[n])
  end
end

"""
---
TensorToolbox:

    full(X::ttensor)
    full(X::ktensor)
    full(X::htensor)

Make full tensor out of a decomposed tensor.
"""
function full(X::ttensor{T}) where {T<:Number}
  ttm(X.cten,X.fmat)
end

"""
   had(X,Y)

Hadamard (element-wise) product of two ttensors. Same as: X.*Y.
"""
function had(X1::ttensor{T1},X2::ttensor{T2}) where {T1<:Number,T2<:Number}
  @assert(size(X1) == size(X2))
	fmat=MatrixCell(ndims(X1)) #initilize factor matrix
  n=1
  for (A1,A2) in zip(X1.fmat,X2.fmat)
      fmat[n]=khatrirao(A1,A2,'t')
      n+=1
	 end
  cten=tkron(X1.cten,X2.cten) #Kronecker product of core tensors
  ttensor(cten,fmat)
end
Base.broadcast(.*,X1::ttensor{T1},X2::ttensor{T2}) where {T1<:Number,T2<:Number}= had(X1,X2)

"""
    hadcten(X,Y,fmat)

Core tensor of Hadamard product of two ttensors with given factor matrices.
"""
function hadcten(X1::ttensor{T1},X2::ttensor{T2},fmat::MatrixCell) where {T1<:Number,T2<:Number}
  N=ndims(X1);
  C=MatrixCell(N)
  for n=1:N
    C[n]=fmat[n]'*khatrirao(X1.fmat[n],X2.fmat[n],'t');
  end
  cten=krontm(X1.cten,X2.cten,C)
end
hadcten(X1::ttensor{T1},X2::ttensor{T2},fmat::Array{Matrix{T3}}) where {T1<:Number,T2<:Number,T3<:Number}=hadcten(X1,X2,MatrixCell(fmat))
#HOSVD for a ttensor. **Documentation in tensor.jl
function hosvd(X::ttensor{T};method="lapack",reqrank=[],eps_abs=[],eps_rel=[]) where {T<:Number}
	F=hosvd(X.cten,method=method,reqrank=reqrank,eps_abs=eps_abs,eps_rel=eps_rel)
  fmat=MatrixCell(ndims(X))
  [fmat[n]=X.fmat[n]*F.fmat[n] for n=1:ndims(X)]
  reorth(ttensor(F.cten,fmat))
end

"""
   hosvd1(X,Y; <keyword arguments>)

Hadamard product of ttensors X and Y as ttensor. Creates the product and calls hosvd.
See also: hosvd2, hosvd3, hosvd4.

## Arguments:
- `method` ∈ {"lapack","lanczos","randsvd"}. Method for SVD. Default: "randsvd".
- `reqrank::Vector`: Requested mutlilinear rank. Optional.
- `eps_abs::Number/Vector`: Drop singular values (of mode-n matricization) below eps_abs. Optional.
- `eps_rel::Number/Vector`: Drop singular values (of mode-n matricization) below eps_rel*sigma_1. Optional.
- `p::Integer`: Oversampling parameter. Defaul p=10.
"""
function hosvd1(X1::ttensor{T1},X2::ttensor{T2};method="randsvd",reqrank=[],eps_abs=[],eps_rel=[],p=10) where {T1<:Number,T2<:Number}
  Xprod=full(X1).*full(X2);
  hosvd(Xprod,method=method,reqrank=reqrank,eps_abs=eps_abs,eps_rel=eps_rel,p=p)
end

"""
   hosvd2(X,Y; <keyword arguments>)

Hadamard product of ttensors X and Y as ttensor. Orthogonalizes factor matrices from structure and calls hosvd on updated core tensor.
See also: hosvd1, hosvd3, hosvd4.

## Arguments:
- `method` ∈ {"lapack","lanczos","randsvd"} Method for SVD. Default: "randsvd".
- `reqrank::Vector`: Requested mutlilinear rank. Optional.
- `eps_abs::Number/Vector`: Drop singular values (of mode-n matricization) below eps_abs. Optional.
- `eps_rel::Number/Vector`: Drop singular values (of mode-n matricization) below eps_rel*sigma_1. Optional.
- `p::Integer`: Oversampling parameter. Defaul p=10.
"""
function hosvd2(X1::ttensor{T1},X2::ttensor{T2};method="randsvd",reqrank=[],eps_abs=[],eps_rel=[],p=10) where {T1<:Number,T2<:Number}
@assert(size(X1) == size(X2))
  N=ndims(X1)
  Q=MatrixCell(N);R=MatrixCell(N);
  n=1
  for (A1,A2) in zip(X1.fmat,X2.fmat)
    Ahad=khatrirao(A1,A2,'t')
    Q[n],R[n]=qr(Ahad)
    n+=1
	 end
  X=hosvd(krontm(X1.cten,X2.cten,R),method=method,reqrank=reqrank,eps_abs=eps_abs,eps_rel=eps_rel,p=p);
  cten=X.cten;
  fmat=MatrixCell(N)
  [fmat[n]=Q[n]*X.fmat[n] for n=1:N];
  ttensor(cten,fmat)
end

"""
   hosvd3(X,Y; <keyword arguments>)

Hadamard product of ttensors X and Y as ttensor. Structure exploiting, works with (X ∗ Y)ₙ(X ∗ Y)ₙᵀ matrices.
See also: hosvd1, hosvd2, hosvd4.

## Arguments:
- `method` ∈ {"lanczos","randsvd"} Structure exploiting method for SVD. Default: "lanczos".
- `reqrank::Vector`: Requested mutlilinear rank. Optional.
- `variant` ∈ {'A','B'} Variant of multiplication (X ∗ Y)ₙ(X ∗ Y)ₙᵀ. Default: 'B'.
- `eps_abs::Number/Vector`: Drop singular values (of mode-n matricization) below eps_abs. Optional.
- `eps_rel::Number/Vector`: Drop singular values (of mode-n matricization) below eps_rel*sigma_1. Optional.
- `p::Integer`: Oversampling parameter. Defaul p=10.
"""
function hosvd3(X1::ttensor{T1},X2::ttensor{T2};method="lanczos",reqrank=[],variant='B',eps_abs=[],eps_rel=[],p=10) where {T1<:Number,T2<:Number}
 	@assert(size(X1) == size(X2))
  N=ndims(X1)
	Ahad=MatrixCell(N) #initilize factor matrices
  if method != "lanczos" && method != "randsvd"
    error("Incorect method name.")
  end
  reqrank=check_vector_input(reqrank,N,0);
  eps_abs=check_vector_input(eps_abs,N,1e-8);
  eps_rel=check_vector_input(eps_rel,N,0);
  @assert(N==length(reqrank),"Dimensions mismatch.")
  for n=1:N
    if method=="lanczos"
      Ahad[n],S=lanczos(X1,X2,n,variant=variant,reqrank=reqrank[n],tol=eps_abs[n],p=p)
    elseif method=="randsvd"
      Ahad[n],S=randsvd(X1,X2,n,variant=variant,reqrank=reqrank[n],tol=eps_abs[n],p=p)
    end
    if reqrank[n] == 0
      eps_rel[n] != 0 ?  tol=eps_rel[n]*S[1] : tol=eps_abs[n];
      I=find(x-> x>tol ? true : false,S)
      Ahad[n]=Ahad[n][:,I];
    end
  end
  core=hadcten(X1,X2,Ahad)
  ttensor(core,Ahad)
end

"""
   hosvd4(X,Y; <keyword arguments>)

Hadamard product of ttensors X and Y as ttensor. Uses rank-1 randomized algorithm for finding range of (X ∗ Y)ₙ.
If reqrank defined, calls additonal hosvd on updated core tensor.
See also: hosvd1, hosvd2, hosvd3.

## Arguments:
- `method` ∈ {"lapack","lanczos","randsvd"} Method for SVD. Default: "lapack".
- `reqrank::Vector`: Requested mutlilinear rank. Optional.
- `eps_abs::Number/Vector`: Drop singular values (of mode-n matricization) below eps_abs. Optional.
- `eps_rel::Number/Vector`: Drop singular values (of mode-n matricization) below eps_rel*sigma_1. Optional.
- `p::Integer`: Oversampling parameter. Defaul p=10.
"""
function hosvd4(X1::ttensor{T1},X2::ttensor{T2};method="lapack",reqrank=[],eps_abs=[],eps_rel=[],p=10) where {T1<:Number,T2<:Number}
  @assert(size(X1) == size(X2))
  N=ndims(X1)
  reqrank=check_vector_input(reqrank,N,0);
  eps_abs=check_vector_input(eps_abs,N,1e-8);
  eps_rel=check_vector_input(eps_rel,N,0);
  Q=MatrixCell(N) #range approximation of tenmat(X1.*X2,n)
  #KR=MatrixCell(N); #transpose Khatri-Rao product of X1.fmat and X2.fmat
  fmat=MatrixCell(N);
  #[KR[n]=khatrirao(X1.fmat[n],X2.fmat[n],'t') for n=1:N]
  KR=khatrirao(X1.fmat,X2.fmat,'t')
  for n=1:N
    Q[n]=randrange(X1.cten,X2.cten,KR,n,reqrank=reqrank[n],tol=eps_abs[n],p=p);
  end
  [fmat[n]=Q[n]'*KR[n] for n=1:N]
  H=krontm(X1.cten,X2.cten,fmat)
  if norm(reqrank) != 0 #fixed-precision problem
    Htucker=hosvd(H,reqrank=reqrank,method=method,eps_abs=eps_abs,eps_rel=eps_rel)
    [fmat[n]=Q[n]*Htucker.fmat[n] for n=1:N]
    return ttensor(Htucker.cten,fmat)
  else
    return ttensor(H,Q)
  end
end

#Inner product of two ttensors. **Documentation in tensor.jl.
function innerprod(X1::ttensor{T1},X2::ttensor{T2}) where {T1<:Number,T2<:Number}
	@assert size(X1) == size(X2)
	if prod(size(X1.cten)) > prod(size(X2.cten))
		innerprod(X2,X1)
	else
    N=ndims(X1)
    fmat=MatrixCell(N)
    [fmat[n]=X1.fmat[n]'*X2.fmat[n] for n=1:N]
		innerprod(X1.cten,ttm(X2.cten,fmat))
	end
end

"""
    isequal(X::ttensor,Y::ttensor)
    isequal(X::ktensor,Y::ktensor)
    isequal(X::ktensor,Y::htensor)

Two tensors in decomposed format are equal if they have equal components. Same as: X==Y.
"""
function isequal(X1::ttensor{T1},X2::ttensor{T2}) where {T1<:Number,T2<:Number}
  if (X1.cten == X2.cten) && (X1.fmat == X2.fmat)
    true
  else
    false
  end
end
==(X1::ttensor{T1},X2::ttensor{T2}) where {T1<:Number,T2<:Number}=isequal(X1,X2)

"""
    lanczos(X,Y,n; <keyword arguments>)

Structure exploiting Lanczos based SVD - computes left singular vectors and singular values of n-mode matricization (X ∗ Y)ₙ.
Works with matrix (X ∗ Y)ₙ(X ∗ Y)ₙᵀ.

## Arguments:
- `reqrank::Integer`: Requested rank. Optional.
- `variant` ∈ {'A','B'} Variant of multiplication (X ∗ Y)ₙ(X ∗ Y)ₙᵀ. Default: 'B'.
- `tol::Number/Vector`: Tolerance. Default: 1e-8.
- `maxit`: Maximal number of iterations. Default: 1000.
- `p::Integer`: Oversampling parameter. Defaul p=10.
"""
function lanczos(X1::ttensor{T1},X2::ttensor{T2},mode::Integer;reqrank=0,variant='B',tol=1e-8,maxit=1000,p=10) where {T1<:Number,T2<:Number}
  @assert(size(X1)==size(X2),"Dimensions mismatch")
  Q,T=lanczos_tridiag(X1,X2,mode,reqrank=reqrank,variant=variant,tol=tol,maxit=maxit,p=p)
  E=eigfact(T,tol,Inf);
  U=E[:vectors][:,end:-1:1];
  S=sqrt.(abs.(E[:values][end:-1:1]));
  if reqrank!=0
    if reqrank > size(U,2)
      warn("Required rank for mode $mode exceeds actual rank, the resulting rank will be ",size(U,2),". Try changing tolerance.");
    else
      U=U[:,1:reqrank];
      S=S[1:reqrank];
    end
  end
  U=Q*U;
  U,S
end

"""
    lanczos_tridiag(X,Y,n; <keyword arguments>)

Structure exploiting Lanczos tridiagonalization algorithm for n-mode matricization A=(X ∗ Y)ₙ(X ∗ Y)ₙᵀ.
Returns orthonormal Q and symmetric tridiagonal T such that A≈Q*T*Q'.


## Arguments:
- `reqrank::Integer`: Requested rank. Optional.
- `variant` ∈ {'A','B'} Variant of multiplication (X ∗ Y)ₙ(X ∗ Y)ₙᵀ. Default: 'B'.
- `tol::Number/Vector`: Tolerance. Default: 1e-8.
- `maxit`: Maximal number of iterations. Default: 1000.
- `p::Integer`: Oversampling parameter. Defaul p=10.
"""
function lanczos_tridiag(X1::ttensor{T1},X2::ttensor{T2},mode::Integer;reqrank=0,variant='B',tol=1e-8,maxit=1000,p=10) where {T1<:Number,T2<:Number}
  I=size(X1)
  m=I[mode]
  n=prod(deleteat!(copy([I...]),mode))
  K=min(m,maxit);
  if reqrank!=0
    K=min(K,reqrank+p);
  end
  α=zeros(K)
  β=zeros(K)
  v=randn(m);
  q=v/norm(v);
  Q=zeros(m,1)
  Q[:,1]=q;
  k=0; #needed if stopping criterion is met
  for k=1:K
    r=mhadtv(X1,X2,Q[:,k],mode,variant=variant)
    α[k]=dot(r,Q[:,k])
    r=r-α[k]*Q[:,k]
    [r=r-Q*(Q'*r) for i=1:3]
    β[k]=norm(r)
    if β[k] < tol
        K=k
      break
    end
    if k!=K
      Q=[Q r/β[k]]
    end
  end
  T=SymTridiagonal(α[1:K], β[1:K-1])
  Q,T
end

"""
    mhadtv(X,Y,v,n,t='b';variant='B')


Mode-n matricized Hadamard product of ttensors X and Y times vector v.
- `t='b'`:  (X ∗ Y)ₙ(X ∗ Y)ₙᵀv. Variant of multiplication (X ∗ Y)ₙ(X ∗ Y)ₙᵀ can be specified to 'A' or 'B'.
- `t='n'`:  (X ∗ Y)ₙᵀv.
- `t='t'`:  (X ∗ Y)ₙᵀv.
If v is a matrix, multiply column by column.
"""
function mhadtv(X1::ttensor{T1},X2::ttensor{T2},v::Vector{T3},n::Integer,t='b';variant='B') where {T1<:Number,T2<:Number,T3<:Number}
  @assert(size(X1)==size(X2),"Dimensions mismatch")
  I=size(X1)
  r1=coresize(X1)
  r2=coresize(X2)
  R=[r1...].*[r2...]
  N=setdiff(1:ndims(X1),n) #all indices but n

  #X1=G₁ ×₁ A₁ ×₂ ... ×ₗ Aₗ
  #X2=G₂ ×₁ B₁ ×₂ ... ×ₗ Bₗ

  if t=='t'
    @assert(length(v) == I[n],"Vector v is of inappropriate size.")
    w1=krtv(X1.fmat[n]',X2.fmat[n]',v); #w1=(Aₖ' ⨀ Bₖ')*v
    W1=mkrontv(X1.cten,X2.cten,w1,n,'t') #W1=tenmat(G₁ ⨂ G₂,n)'*w1
    for k in N
      W1=reshape(W1,R[k],round.(Int,prod(size(W1))/R[k]))
      W2=tkrtv(X1.fmat[k],X2.fmat[k],W1) #vec(W2)=(Aₖ ⨀' Bₖ)*vec(W1)
      W1=W2'
    end
    vec(W1)
  elseif t=='n'
    @assert(length(v) == prod(deleteat!(copy(collect(I)),n)),"Vector v is of inappropriate size.")
    W1=v
    for k in N
      W1=reshape(W1,I[k],round.(Int,prod(size(W1))/I[k]))
      W2=krtv(X1.fmat[k]',X2.fmat[k]',W1) #W2=(Aₖ' ⨀ Bₖ')*W1
      W1=W2'
    end
    W2=mkrontv(X1.cten,X2.cten,vec(W1),n) #W1=tenmat(G₁ ⨂ G₂),n)*vec(W2)
    tkrtv(X1.fmat[n],X2.fmat[n],W2) #(Aₖ ⨀' Bₖ)*W2
  elseif t=='b'
    @assert(length(v) == I[n],"Vector v is of inappropriate size.")
    if variant == 'A'    #use when prod(I[N])-prod(R[N]) < 0
      mhadtv(X1,X2,mhadtv(X1,X2,v,n,'t'),n,'n')
    elseif variant == 'B'
      w1=krtv(X1.fmat[n]',X2.fmat[n]',v); #w1=(Aₖ' ⨀ Bₖ')*v
      W1=mkrontv(X1.cten,X2.cten,w1,n,'t') #W1=tenmat(G₁ ⨂ G₂,n)'*w1
      for k in N
        W1=reshape(W1,R[k],round.(Int,prod(size(W1))/R[k]))
        W2=tkrtv(X1.fmat[k],X2.fmat[k],W1)
        W1=krtv(X1.fmat[k]',X2.fmat[k]',W2)'
      end
      W2=mkrontv(X1.cten,X2.cten,vec(W1),n) #W2=tenmat(G₁ ⨂ G₂),n)*vec(W1)
      tkrtv(X1.fmat[n],X2.fmat[n],W2) #(Aₖ' ⨀ Bₖ')'*W2
    else
      error("Variant should be either 'A' or 'B'.")
    end
  end
end
function mhadtv(X1::ttensor{T1},X2::ttensor{T2},M::Matrix{T3},n::Integer,t='b';variant='B') where {T1<:Number,T2<:Number,T3<:Number}
  @assert(size(X1)==size(X2),"Dimensions mismatch")
    if sort(collect(size(vec(M))))[1]==1
        return mhadtv(X1,X2,vec(M),n,t,variant=variant);
  end
  I=size(X1)
  In=I[n]
  Im=prod(deleteat!(copy([I...]),n))
  if t=='n'
    @assert(size(M,1) == Im, "Dimensions mismatch")
    Mprod=zeros(In,size(M,2))
  elseif t=='t'
    @assert(size(M,1) == In, "Dimensions mismatch")
    Mprod=zeros(Im,size(M,2))
  elseif t=='b'
    @assert(size(M,1) == In, "Dimensions mismatch")
    Mprod=zeros(In,size(M,2))
  end
  [Mprod[:,j]=  mhadtv(X1,X2,M[:,j],n,t,variant=variant) for j=1:size(M,2)]
  Mprod
end

function mhadtm(X1::ttensor{T1},X2::ttensor{T2},M::Matrix{T3},n::Integer,t='b';variant='B') where {T1<:Number,T2<:Number,T3<:Number}
  warn("Function mhadtm is depricated. Use mhadtv.")
  mhadtm(X1,X2,M,n,t,variant=variant)
end

"""
    minus(X::ttensor,Y::ttensor)
    minus(X::ktensor,Y::ktensor)
    minus(X::htensor,Y::htensor)

Subtraction of two tensors. Same as: X-Y.
"""
function minus(X1::ttensor{T1},X2::ttensor{T2}) where {T1<:Number,T2<:Number}
  X1+(-1)*X2
end
-(X1::ttensor{T1},X2::ttensor{T2}) where {T1<:Number,T2<:Number}=minus(X1,X2)


#Multilinear rank of a ttensor. **Documentation in tensor.jl.
function mrank(X::ttensor{T}) where {T<:Number}
  ntuple(n->nrank(X,n),ndims(X))
end
function mrank(X::ttensor{T},tol::Number) where {T<:Number}
   ntuple(n->nrank(X,n,tol),ndims(X))
end

"""
   msvdvals(X,n)

Singular values of mode-n matricization of a ttensor calculated directly. See also: nvecs.
"""
function msvdvals(X::ttensor{T},n::Integer) where {T<:Number}
  if X.isorth != true
    reorth!(X)
  end
  Gn=tenmat(X.cten,n)
  svdvals(Gn)
end

"""
    mtimes(a,X)

Scalar times ttensor. Same as: a*X.
"""
function mtimes(α::Number,X::ttensor{T}) where {T<:Number}
	ttensor(α*X.cten,X.fmat);
end
*(α::T1,X::ttensor{T2}) where {T1<:Number,T2<:Number}=mtimes(α,X)
*(X::ttensor{T1},α::T2) where {T1<:Number,T2<:Number}=*(α,X)

#Matricized ttensor times Khatri-Rao product. **Documentation in tensor.jl.
function mttkrp(X::ttensor{T},M::MatrixCell,n::Integer) where {T<:Number}
  N=ndims(X)
  @assert(length(M) == N,"Wrong number of matrices.")
  modes=setdiff(1:N,n)
  I=[size(X)...]
  K=size(M[modes[1]],2)
  @assert(!any(map(Bool,[size(M[m],2)-K for m in modes])),"Matrices must have the same number of columns")
  @assert(!any(map(Bool,[size(M[m],1)-I[m] for m in modes])),"Matrices are of wrong size")
  Y=mttkrp(X.cten,vec(X.fmat[modes]').*M[modes],n)
  X.fmat[n]*Y
end
mttkrp(X::ttensor{T1},M::Array{Matrix{T2}},n::Integer) where {T1<:Number,T2<:Number}=mttkrp(X,MatrixCell(M),n)

#Number of modes of a ttensor. **Documentation in Base.
function ndims(X::ttensor{T}) where {T<:Number}
	ndims(X.cten)
end

#n-rank of a ttensor. **Documentation in tensor.jl.
function nrank(X::ttensor{T},n::Integer) where {T<:Number}
  rank(X.fmat[n])
end
function nrank(X::ttensor{T},n::Integer,tol::Number) where {T<:Number}
  rank(X.fmat[n],tol)
end

#Computes the r leading left singular vectors of mode-n matricization of a tensor X. **Documentation in tensor.jl.
function nvecs(X::ttensor{T},n::Integer,r=0;flipsign=false) where {T<:Number}
  if r==0
    r=size(X,n)
  end
  N=ndims(X)
  V=MatrixCell(N)
  V[n]=X.fmat[n]
  for m in setdiff(1:N,n)
    V[m]=X.fmat[m]'*X.fmat[m]
  end
  H=ttm(X.cten,V)
  Hn=tenmat(H,n)
  Gn=tenmat(X.cten,n)
  #V=eigs(Symmetric(Hn*Gn'*X.fmat[n]'),nev=r,which=:LM)[2] #has bugs
  V=eigfact(Symmetric(Hn*Gn'*X.fmat[n]'))[:vectors][:,end:-1:end-r+1]
  if flipsign
      maxind = findmax(abs.(V),1)[2]
      for i = 1:r
          ind=ind2sub(size(V),maxind[i])
          if V[ind...] < 0
             V[:,ind[2]] = V[:,ind[2]] * -1
          end
      end
  end
  V
end

#Permute dimensions of a ttensor. **Documentation in Base.
function permutedims(X::ttensor{T},perm::Vector{D}) where {T<:Number,D<:Integer}
  @assert(collect(1:ndims(X))==sort(perm),"Invalid permutation")
  cten=permutedims(X.cten,perm)
  fmat=X.fmat[perm]
  ttensor(cten,fmat)
end

"""
    plus(X::ttensor,Y::ttensor)
    plus(X::ktensor,Y::ktensor)
    plus(X::htensor,Y::htensor)

Addition of two tensors. Same as: X+Y.
"""
function plus(X1::ttensor{T1},X2::ttensor{T2}) where {T1<:Number,T2<:Number}
	@assert(size(X1) == size(X2),"Dimension mismatch.")
	fmat=Matrix[[X1.fmat[n] X2.fmat[n]] for n=1:ndims(X1)] #concatenate factor matrices
  cten=blockdiag(X1.cten,X2.cten)
	ttensor(cten,fmat)
end
+(X1::ttensor{T1},X2::ttensor{T2}) where {T1<:Number,T2<:Number}=plus(X1,X2)

"""
    randrange(X,Y,n; <keyword arguments>)

Structure exploiting randomized range approximation of n-mode matricization of Hadamard product (X ∗ Y)ₙ, where X and Y are ttensors.

### Arguments:
- `reqrank::Integer`: Requested rank. Optional.
- `tol::Number/Vector`: Tolerance. Default: 1e-8.
- `maxit`: Maximal number of iterations. Default: 1000.
- `r`: Number of samples for stopping criterion. Default: r=10.
- `p::Integer`: Oversampling parameter. Defaul p=10.
"""
function randrange(X1::ttensor{T1},X2::ttensor{T2},mode::Integer;tol=1e-8,maxit=1000,reqrank=0,p=10,r=10) where {T1<:Number,T2<:Number}
  @assert(size(X1) == size(X2))
  N=ndims(X1)
  KR=MatrixCell(N); #transpose Khatri-Rao product of X1.fmat and X2.fmat
  [KR[n]=khatrirao(X1.fmat[n],X2.fmat[n],'t') for n=1:N]
  randrange(X1.cten,X2.cten,KR,mode,tol=tol,maxit=maxit,reqrank=reqrank,p=p,r=r)
end

function randrange(C1::Array{T1,N},C2::Array{T2,N},KR::MatrixCell,mode::Integer;tol=1e-8,maxit=1000,reqrank=0,p=10,r=10) where {T1<:Number,T2<:Number,N}
  I=zeros(Int,N)
  [I[n]= size(KR[n],1) for n=1:N]
  m=I[mode]
  n=prod(deleteat!(copy([I...]),mode))
  remmodes=setdiff(1:N,mode);
  y=VectorCell(N-1);
  if reqrank!=0
    Y=zeros(m,reqrank+p);
    for i=1:reqrank+p
      [y[k]=randn(size(KR[remmodes[k]],1)) for k=1:N-1]
      w=krontkron(reverse(KR[remmodes]),reverse(y),'t')
      Y[:,i]=KR[mode]*mkrontv(C1,C2,w,mode)
    end
    #Q=full(qrfact(Y)[:Q]);
    Q=qr(Y)[1];
  else
    maxit=min(m,n,maxit);
    rangetol=tol*sqrt.(pi/2)/10;
    Y=zeros(m,r);
    for i=1:r
      [y[k]=randn(size(KR[remmodes[k]],1)) for k=1:N-1]
      w=krontkron(reverse(KR[remmodes]),reverse(y),'t')
      Y[:,i]=KR[mode]*mkrontv(C1,C2,w,mode);
    end
    j=0;
    Q=zeros(m,0);
    maxcolnorm=maximum([norm(Y[:,i]) for i=1:r]);
    while maxcolnorm > rangetol && j<maxit
      j+=1;
      p=Q'*Y[:,j];
      Y[:,j]-=Q*p;
      q=Y[:,j]/norm(Y[:,j]);
      Q=[Q q];
      [y[k]=randn(size(KR[remmodes[k]],1)) for k=1:N-1]
      w=krontkron(reverse(KR[remmodes]),reverse(y),'t')
      w=KR[mode]*mkrontv(C1,C2,w,mode);
      p=Q'*w;
      Y=[Y w-Q*p]; #Y[:,j+r]=w-Q*p;
      p=q'*Y[:,j+1:j+r-1]
      Y[:,j+1:j+r-1]-=q*p;
      maxcolnorm=maximum([norm(Y[:,i]) for i=j+1:j+r]);
    end
  end
  Q
end
randrange(C1::Array{T1,N},C2::Array{T2,N},KR::Array{Matrix{T3}},mode::Integer;tol=1e-8,maxit=1000,reqrank=0,p=10,r=10) where {T1<:Number,T2<:Number,T3<:Number,N}=randrange(C1,C2,MatrixCell(KR),mode,tol,maxit,reqrank,p,r)

"""
    randsvd(X,Y,n; <keyword arguments>)

Structure exploiting randomized SVD - computes left singular vectors and singular values of n-mode matricization (X ∗ Y)ₙ.
Works with matrix (X ∗ Y)ₙ(X ∗ Y)ₙᵀ.

## Arguments:
- `reqrank::Integer`: Requested rank. Optional.
- `variant` ∈ {'A','B'} Variant of multiplication (X ∗ Y)ₙ(X ∗ Y)ₙᵀ. Default: 'B'.
- `tol::Number/Vector`: Tolerance. Default: 1e-8.
- `maxit`: Maximal number of iterations. Default: 1000.
- `r`: Number of samples for stopping criterion. Default: r=10.
- `p::Integer`: Oversampling parameter. Defaul p=10.
"""
function randsvd(X1::ttensor{T1},X2::ttensor{T2},mode::Integer;variant='B',tol=1e-8,maxit=1000,reqrank=0,p=10,r=10) where {T1<:Number,T2<:Number}
  @assert(size(X1)==size(X2),"Dimensions mismatch")
  I=size(X1)
  m=I[mode]
  n=prod(deleteat!(copy([I...]),mode))
  if reqrank!=0
     Y=mhadtv(X1,X2,randn(m,reqrank+p),mode,variant=variant);  #Y=A*(A'*randn(m,reqrank+p));
     #Q=full(qrfact(Y)[:Q]);
     Q=qr(Y)[1];
  else
    maxit=min(m,n,maxit);
    rangetol=tol*sqrt.(pi/2)/10;
    Y=mhadtv(X1,X2,randn(m,r),mode,variant=variant);  #Y=A*(A'*randn(m,r));
    j=0;
    Q=zeros(m,0);
    maxcolnorm=maximum([norm(Y[:,i]) for i=1:r]);
    while maxcolnorm > rangetol && j<maxit
      j+=1;
      p=Q'*Y[:,j];
      Y[:,j]-=Q*p;
      q=Y[:,j]/norm(Y[:,j]);
      Q=[Q q];
      w=mhadtv(X1,X2,randn(m),mode,variant=variant); #w=A*(A'*randn(m));
      p=Q'*w;
      Y=[Y w-Q*p]; #Y[:,j+r]=w-Q*p;
      p=q'*Y[:,j+1:j+r-1]
      Y[:,j+1:j+r-1]-=q*p;
      maxcolnorm=maximum([norm(Y[:,i]) for i=j+1:j+r]);
    end
  end
  B=mhadtv(X1,X2,Q,mode,'t');#B=A'*Q;
  B=Symmetric(B'*B);
  #or (faster for small rank):
  #B=mhadtv(X1,X2,Q,mode,'n');
  #B=Symmetric(Q'*B);
  E=eigfact(B,tol,Inf);
  U=E[:vectors][:,end:-1:1];
  S=sqrt.(abs.(E[:values][end:-1:1]));
  if reqrank != 0
    if reqrank > size(U,2)
      warn("Required rank for mode $mode exceeds actual rank, the resulting rank will be smaller.")
    else
      U=U[:,1:reqrank];
      S=S[1:reqrank];
    end
  end
  U=Q*U;
  U,S
end

"""
      reorth(X::ttensor)
      reorth(X::htensor)

Orthogonalize factor matrices of a tensor.
"""
function reorth(X::ttensor{T}) where {T<:Number}
  N=ndims(X)
	if X.isorth
		X
	else
		Q=MatrixCell(N)
		R=MatrixCell(N)
    n=1;
		for A in X.fmat
			Qt,Rt=qr(A)
			Q[n]=Qt
			R[n]=Rt
      n+=1
		end
		ttensor(ttm(X.cten,R),Q)
	end
end

"""
    reorth!(X::ttensor)
    reorth!(X::htensor)

Orthogonalize factor matrices of a tensor. Rewrite ttensor.
"""
function reorth!(X::ttensor{T}) where {T<:Number}
	if X.isorth != true
		for n=1:ndims(X)
			Q,R=qr(X.fmat[n])
			X.fmat[n]=Q
			X.cten=ttm(X.cten,R,n)
		end
    X.isorth=true;
  end
  X
end

#Size of a ttensor. **Documentation in Base.
function size(X::ttensor{T}) where {T<:Number}
	tuple([size(X.fmat[n],1) for n=1:ndims(X)]...)
end
#Size of n-th mode of a ttensor.
function size(X::ttensor{T},n::Integer) where {T<:Number}
  size(X.fmat[n],1)
end

function Base.show(io::IO,X::ttensor{T}) where {T<:Number}
    display(X)
end

#Mode-n matricization of a ttensor. **Documentation in tensor.jl.
tenmat(X::ttensor{T},n::Integer) where {T<:Number}=tenmat(full(X),n)

#ttensor times matrix (n-mode product). **Documentation in tensor.jl.
#t='t' transposes matrices
function ttm(X::ttensor{T},M::MatrixCell,modes::Vector{D},t='n') where {T<:Number,D<:Integer}
  if t=='t'
	 M=vec(M')
	end
	@assert(length(modes)<=length(M),"Too few matrices")
	@assert(length(M)<=ndims(X),"Too many matrices")
  if length(modes)<length(M)
    M=M[modes]
  end
  fmat=copy(X.fmat)
  for n=1:length(modes)
    fmat[modes[n]]=M[n]*X.fmat[modes[n]]
  end
    ttensor(X.cten,fmat)
end
ttm(X::ttensor{T},M::MatrixCell,modes::AbstractRange{D},t='n') where {T<:Number,D<:Integer}=ttm(X,M,collect(modes),t)
ttm(X::ttensor{T1},M::Matrix{T2},n::Integer,t='n') where {T1<:Number,T2<:Number}=ttm(X,[M],[n],t)
ttm(X::ttensor{T},M::MatrixCell,t::Char) where {T<:Number}=ttm(X,M,1:length(M),t)
ttm(X::ttensor{T},M::MatrixCell) where {T<:Number}=ttm(X,M,1:length(M))
function ttm(X::ttensor{T},M::MatrixCell,n::Integer,t='n') where {T<:Number}
	if n>0
		ttm(X,M[n],n,t)
	else
		modes=setdiff(1:ndims(X),-n)
		ttm(X,M,modes,t)
	end
end
#If array of matrices isn't defined as MatrixCell, but as M=[M1,M2,...,Mn]:
ttm(X::ttensor{T1},M::Array{Matrix{T2}},modes::Vector{D},t='n') where {T1<:Number,T2<:Number,D<:Integer}=ttm(X,MatrixCell(M),modes,t)
ttm(X::ttensor{T1},M::Array{Matrix{T2}},modes::AbstractRange{D},t='n') where {T1<:Number,T2<:Number,D<:Integer}=ttm(X,MatrixCell(M),modes,t)
ttm(X::ttensor{T1},M::Array{Matrix{T2}},t::Char) where {T1<:Number,T2<:Number}=ttm(X,MatrixCell(M),t)
ttm(X::ttensor{T1},M::Array{Matrix{T2}}) where {T1<:Number,T2<:Number}=ttm(X,MatrixCell(M))
ttm(X::ttensor{T1},M::Array{Matrix{T2}},n::Integer,t='n') where {T1<:Number,T2<:Number}=ttm(X,MatrixCell(M),n,t)

#ttensor times vector (n-mode product). **Documentation in tensor.jl.
#t='t' transposes matrices
function ttv(X::ttensor{T},V::VectorCell,modes::Vector{D}) where {T<:Number,D<:Integer}
  N=ndims(X)
  remmodes=setdiff(1:N,modes)
  fmat=VectorCell(N)
  if length(modes) < length(V)
    V=V[modes]
  end
  for n=1:length(modes)
    fmat[modes[n]]=X.fmat[modes[n]]'*V[n]
  end
  cten=ttv(X.cten,fmat,modes)
  if isempty(remmodes)
    cten
  else
    ttensor(cten,X.fmat[remmodes])
  end
end
ttv(X::ttensor{T1},v::Vector{T2},n::Integer) where {T1<:Number,T2<:Number}=ttv(X,Vector[v],[n])
ttv(X::ttensor{T},V::VectorCell,modes::AbstractRange{D}) where {T<:Number,D<:Integer}=ttv(X,V,collect(modes))
ttv(X::ttensor{T},V::VectorCell) where {T<:Number}=ttv(X,V,1:length(V))
function ttv(X::ttensor{T},V::VectorCell,n::Integer) where {T<:Number}
	if n>0
		ttm(X,V[n],n)
	else
		modes=setdiff(1:ndims(X),-n)
		ttm(X,A,modes)
	end
end
#If array of vectors isn't defined as VectorCell, but as V=[v1,v2,...,vn]:
ttv(X::ttensor{T1},V::Array{Vector{T2}},modes::Vector{D}) where {T1<:Number,T2<:Number,D<:Integer}=ttv(X,VectorCell(V),modes)
ttv(X::ttensor{T1},V::Array{Vector{T2}},modes::AbstractRange{D}) where {T1<:Number,T2<:Number,D<:Integer}=ttv(X,VectorCell(V),modes)
ttv(X::ttensor{T1},V::Array{Vector{T2}}) where {T1<:Number,T2<:Number}=ttv(X,VectorCell(V))
ttv(X::ttensor{T1},V::Array{Vector{T2}},n::Integer) where {T1<:Number,T2<:Number}=ttv(X,VectorCell(V),n)

"""
   uminus(X::ttensor)
   uminus(X::ktensor)
   uminus(X::htensor)

Unary minus. Same as: (-1)*X.
"""
uminus(X::ttensor{T}) where {T<:Number}=mtimes(-1,X)
-(X::ttensor{T}) where {T<:Number}=uminus(X)

#Frobenius norm of a ttensor. **Documentation in Base.
function norm(X::ttensor{T}) where {T<:Number}
	if prod(size(X)) > prod(size(X.cten))
		if X.isorth
			norm(X.cten)
		else
			R=MatrixCell(ndims(X))
			for n=1:ndims(X)
				#R[n]=qrfact(X.fmat[n])[:R]
				R[n]=qr(X.fmat[n])[2];
			end
			norm(ttm(X.cten,R))
		end
	else
		norm(full(X))
	end
end
