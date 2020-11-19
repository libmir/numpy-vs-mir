module multid.multigrid.cycle;

import mir.conv : to;
import mir.exception : enforce;
import mir.math : log2;
import mir.ndslice : Slice, slice, iota, sliced;
import multid.gaussseidel.redblack : SweepType;
import multid.multigrid.prolongation : prolongation;
import std.traits : isFloatingPoint;

/++
    Abstract base class for the Cycles it implements the base MG sheme
+/
class Cycle(T, size_t Dim) if (1 <= Dim && Dim <= 3 && isFloatingPoint!T)
{
protected:
    uint mu, l;
    Slice!(T*, Dim) F;
    T[] Rdata;

    final auto R(size_t[Dim] shape)
    {
        return Rdata[0 .. shape.iota.elementCount].sliced(shape);
    }

    T h;

    abstract @nogc void presmooth(Slice!(T*, Dim) F, Slice!(T*, Dim) U, T current_h);
    abstract @nogc void postsmooth(Slice!(T*, Dim) F, Slice!(T*, Dim) U, T current_h);
    abstract @nogc Slice!(T*, Dim) compute_residual(Slice!(T*, Dim) F, Slice!(T*, Dim) U, T current_h);
    abstract @nogc void solve(Slice!(T*, Dim) F, Slice!(T*, Dim) U, T current_h);
    abstract Slice!(T*, Dim) restriction(Slice!(T*, Dim) U);

    Slice!(T*, Dim) compute_correction(Slice!(T*, Dim) r, uint l, T current_h)
    {
        auto e = slice!T(r.shape, 0);
        foreach (_; 0 .. mu)
        {
            do_cycle(r, e, l, current_h);
        }
        return e;
    }

    /++ adds the correction vector to the U +/
    @nogc void add_correction(Slice!(T*, Dim) U, Slice!(const(T)*, Dim) e)
    {

        U.field[] += e.field[];
    }

    void do_cycle(Slice!(T*, Dim) F, Slice!(T*, Dim) U, uint l, T current_h)
    {
        if (l <= 1 || U.shape[0] <= 1)
        {
            solve(F, U, current_h);
            return;
        }

        presmooth(F, U, current_h);

        auto r = compute_residual(F, U, current_h);

        r = restriction(r);

        r = compute_correction(r, l - 1, current_h * 2);

        auto e = R(U.shape);
        prolongation!(T, Dim)(r, e);

        add_correction(U, e);

        postsmooth(F, U, current_h);
    }

public:
    /++
       Constructor for Cycle
       Params:
        F = Dim-slice as righthandsite
        mu = indicator for type of cycle
        l = the depth of the multigrid cycle if it is set to 0, the maxmium depth is choosen
        h = is the distance between the grid points if set to 0 1 / F.shape[0] is used
    +/
    this(Slice!(T*, Dim) F, uint mu, uint l, T h)
    {
        auto ls = F.shape[0].to!double.log2;
        enforce!"l is to big for F"(l == 0 || ls > l);
        this.F = F;
        this.Rdata = F.shape.slice!double.field;
        this.l = l;
        this.h = h != 0 ? h : 1.0 / F.shape[0];
        this.mu = mu;
        if (this.l == 0)
        {
            this.l = ls.to!uint - 1;
        }
    }

    /++
        This computes the residual
    +/
    @nogc Slice!(T*, Dim) residual(Slice!(T*, Dim) F, Slice!(T*, Dim) U)
    {
        return compute_residual(F, U, this.h);
    }

    /++
        The actual function to caculate a cycle
    +/
    void cycle(Slice!(T*, Dim) U)
    {
        do_cycle(this.F, U, this.l, this.h);
    }

    /++ Computes the l2 norm of U and the inital F+/
    @nogc abstract T norm(Slice!(T*, Dim) U);
}

/++ Poisson Cycle:
    T = a floatingpoint datatype
    Dim = dimension {1,2,3}
    v1 = number of presmoothing steps
    v2 = number of postsmoothing steps
    eps = the epsilon the is used in the cycle esspecially in the solve step as stopcriteria
+/
class PoissonCycle(T, size_t Dim, uint v1, uint v2, SweepType sweep = SweepType.field,
        T eps = 1e-8) : Cycle!(T, Dim) if (1 <= Dim && Dim <= 3 && isFloatingPoint!T)
{
    import multid.gaussseidel.redblack : GS_RB;

protected:
    override void presmooth(Slice!(T*, Dim) F, Slice!(T*, Dim) U, T current_h)
    {
        auto r = R(F.shape);
        T norm;
        auto it = GS_RB!(v1, 1_000, eps, sweep)(F, U, r, current_h, norm);
    }

    override void postsmooth(Slice!(T*, Dim) F, Slice!(T*, Dim) U, T current_h)
    {
        auto r = R(F.shape);
        T norm;
        auto it = GS_RB!(v2, 1_000, eps, sweep)(F, U, r, current_h, norm);
    }

    override Slice!(T*, Dim) compute_residual(Slice!(T*, Dim) F, Slice!(T*, Dim) U, T current_h)
    {
        import ap = multid.tools.apply_poisson;

        auto r = R(F.shape);
        ap.compute_residual!(T, Dim)(r, F, U, current_h);
        return r;
    }

    override void solve(Slice!(T*, Dim) F, Slice!(T*, Dim) U, T current_h)
    {
        auto r = R(F.shape);
        T norm;
        auto it = GS_RB!(100_000, 5, eps, sweep)(F, U, r, current_h, norm);
    }

    override Slice!(T*, Dim) restriction(Slice!(T*, Dim) U)
    {
        import multid.multigrid.restriction : weighted_restriction;

        return weighted_restriction!(T, Dim)(U);
    }

public:
    /++
       Params:
        F = Dim-slice as righthandside
        mu = indicator for type of cycle
        l = the depth of the multigrid cycle if it is set to 0, the maxmium depth is choosen
        h = is the distance between the grid points if set to 0 1 / F.shape[0] is used
    +/
    this(Slice!(T*, Dim) F, uint mu, uint l, T h)
    {
        super(F, mu, l, h);
    }

    override T norm(Slice!(T*, Dim) U)
    {
        import multid.tools.norm : nrmL2;

        auto res = residual(F, U);
        return nrmL2(res);
    }
}

unittest
{
    import mir.algorithm.iteration : all;
    import multid.tools.util : randomMatrix;

    const size_t N = 10;
    immutable h = 1.0 / N;

    auto U = randomMatrix!(double, 2)(N);

    U[0][0 .. $] = 1.0;
    U[1 .. $, 0] = 1.0;
    U[$ - 1][1 .. $] = 0.0;
    U[1 .. $, $ - 1] = 0.0;

    auto F = slice!double([N, N], 0.0);
    import multid.tools.apply_poisson : compute_residual;
    import multid.tools.norm : nrmL2;

    const auto norm_before = compute_residual(F, U, h).nrmL2;
    F[0][0 .. $] = 1.0;
    F[1 .. $, 0] = 1.0;
    F[$ - 1][1 .. $] = 0.0;
    F[1 .. $, $ - 1] = 0.0;
    auto p = new PoissonCycle!(double, 2, 2, 2)(F, 2, 0, h);
    p.cycle(U);

    const auto norm_after = compute_residual(F, U, h).nrmL2;

    assert(U[0][0 .. $].all!"a == 1.0");
    assert(U[1 .. $, 0].all!"a == 1.0");
    assert(U[$ - 1][1 .. $].all!"a == 0.0");
    assert(U[1 .. $, $ - 1].all!"a == 0.0");

    // it should be at least a bit smaller than before
    assert(norm_after <= norm_before);
}
