using BlockDiagonals

struct LQD{
  E,
  T<:AbstractMatrix{E},
  V<:AbstractVector{E},
  VI<:AbstractVector{Int64},
} <: Factorization{E}
  LorUdata::T
  Qdata::T
  ipiv::VI
  uplo::Char
  d::V
  s::VI
  p::VI

  function LQD(
    LorUdata::T,
    Qdata::T,
    ipiv::VI,
    uplo::Char,
    d::V,
    s::VI,
    p::VI,
    ) where {E,T<:AbstractMatrix{E},V<:AbstractVector{E},VI<:AbstractVector} 

    Base.require_one_based_indexing(LorUdata, Qdata)
    new{E,T,V,VI}(LorUdata, Qdata, ipiv, uplo, d, s, p)
  end
end

function lqd!(A::Hermitian{E, <:AbstractMatrix{E}}) where {E}
  F = bunchkaufman!(A, true)
  n, _ = size(A)
  s = similar(F.p)
  uplo = F.uplo == 'U' ? :U : :L
  LorUdata = uplo == :U ? copy(F.U).data : copy(F.L).data
  Qdata = similar(F.LD, n, 2)
  Qdata .= zero(eltype(Qdata))
  d = similar(F.LD, n)
  j = 1
  while j <= n
    if F.ipiv[j] >= 1
      Qdata[j, 1] = one(eltype(Qdata))
      d[j] = sqrt(abs(F.LD[j, j]))
      s[j] = sign(F.LD[j, j])
      j += 1
    else
      dj, Qj = eigen(Hermitian(view(F.LD, j:(j + 1), j:(j + 1)), uplo))
      d[j:(j + 1)] .= sqrt.(abs.(dj))
      s[j:(j + 1)] .= sign.(dj)
      Qdata[j:(j + 1), :] .= Qj
      j += 2
    end
  end

  return LQD(LorUdata, Qdata, F.ipiv, F.uplo, d, s, F.p)
end

lqd(A::Hermitian{E,<:AbstractMatrix{E}}) where {E} = lqd!(copy(A))

function Base.getproperty(F::LQD, sym::Symbol)
  if sym === :D
    return Diagonal(getfield(F, :d))
  elseif sym === :L
    getfield(F, :uplo) == 'U' &&
      throw(ArgumentError("factorization is U*Q*D*S*D*Q'*U' but you requested L."))
    return UnitLowerTriangular(getfield(F, :LorUdata))
  elseif sym === :U
    getfield(F, :uplo) == 'L' &&
      throw(ArgumentError("factorization is L*Q*D*S*D*Q'*L' but you requested U."))
    return UnitUpperTriangular(getfield(F, :LorUdata))
  elseif sym === :S
    return Diagonal(getfield(F, :s))
  elseif sym === :Q
    Qdata = getfield(F, :Qdata)
    ipiv = getfield(F, :ipiv)
    n = length(ipiv)
    Qv = Vector{typeof(view(Qdata, 1:1, 1:1))}(undef, n)
    j = 1
    blocks = 0
    while j <= n
      if ipiv[j] >= 1
        blocks += 1
        Qv[blocks] = view(Qdata, j:j, 1:1)
        j += 1
      else
        blocks += 1
        Qv[blocks] = view(Qdata, j:(j + 1), 1:2)
        j += 2
      end
    end
    return BlockDiagonal(Qv[1:blocks])
  else
    return getfield(F, sym)
  end
end

Base.size(lqd::LQD) = size(lqd.LorUdata)
Base.size(lqd::Adjoint{<:LQD}) = size(lqd.parent.LorUdata)

function Base.show(io::IO, mime::MIME"text/plain", lqd::LQD)
  summary(io, lqd)
  println(io)
  println(io, "$(lqd.uplo) factor:")
  show(io, mime, lqd.uplo == 'L' ? lqd.L : lqd.U)
  println(io, "\nQ factor:")
  show(io, mime, lqd.Q)
  println(io, "\nD factor:")
  show(io, mime, lqd.D)
  println(io, "\nS factor:")
  show(io, mime, lqd.S)
end

function Base.:*(
  lqd::LQD{E},
  A::VecOrMat{E},
  ) where {E}
  return ((lqd.uplo == 'L' ? lqd.L : lqd.U) * (lqd.Q * (lqd.D * A)))[
    invperm(lqd.p),
    :,
  ]
end

function Base.:*(
  A::VecOrMat{E},
  lqd::LQD{E},
  ) where {E}
  return ((A[:,lqd.p] * (lqd.uplo == 'L' ? lqd.L : lqd.U)) * lqd.Q) * lqd.D
end

function Base.:\(
  lqd::LQD{E},
  A::VecOrMat{E},
  ) where {E}
  return lqd.D \ (lqd.Q' * ((lqd.uplo == 'L' ? lqd.L : lqd.U) \ A[lqd.p, :]))
end

function Base.:/(
  A::VecOrMat{E},
  lqd::LQD{E},
  ) where {E}
  return (((A / lqd.D) * lqd.Q') / (lqd.uplo == 'L' ? lqd.L : lqd.U))[:, invperm(lqd.p)]
end

Base.adjoint(lqd::T) where {E, T <: LQD{E}} = Adjoint{E, T}(lqd)

Base.adjoint(adjlqd::Adjoint{E,T}) where {E, T <: LQD{E}} = adjlqd.parent

function Base.:*(adjlqd::Adjoint{E,<:LQD{E}}, A::VecOrMat{E}) where {E}
  lqd = adjlqd.parent
  return lqd.D' * (lqd.Q' * ((lqd.uplo == 'L' ? lqd.L : lqd.U)' * A[lqd.p, :]))
end

function Base.:*(A::VecOrMat{E}, adjlqd::Adjoint{E,<:LQD{E}}) where {E}
  lqd = adjlqd.parent
  return (((A * lqd.D') * lqd.Q') * (lqd.uplo == 'L' ? lqd.L : lqd.U)')[
    :,
    invperm(lqd.p),
  ]
end

function Base.:/(
  A::VecOrMat{E},
  adjlqd::Adjoint{E, <:LQD{E}},
  ) where {E}
  lqd = adjlqd.parent
  return ((A[:, lqd.p] / (lqd.uplo == 'L' ? lqd.L : lqd.U)') * lqd.Q) / lqd.D'
end

function Base.:\(adjlqd::Adjoint{E,<:LQD{E}}, A::VecOrMat{E}) where {E}
  lqd = adjlqd.parent
  return ((lqd.uplo == 'L' ? lqd.L : lqd.U)' \ (lqd.Q * (lqd.D' \ A)))[
    invperm(lqd.p),
    :,
  ]
end

function Base.Matrix(F::LQD{E}) where E
  n, _ = size(F)
  return F * Matrix{E}(I, n, n)
end
