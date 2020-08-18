module multid.gaussseidel.redblack;

import multid.tools.apply_poisson;

import std.stdio;
import mir.ndslice;
import std.traits : isFloatingPoint;
import std.range;
import std.stdio : writeln;
import pretty_array;

/++
    red is for even indicies
    black for the odd
+/
enum Color
{
    red = 0u,
    black = 1u
}

/++
This is a Gauss Seidel Red Black implementation for 1D
+/
Slice!(T*, Dim) GS_RB(T, size_t Dim, size_t max_iter = 10_000_000,
        size_t norm_iter = 10_000, double eps = 1e-8)(Slice!(T*, Dim) F, Slice!(T*, Dim) U, T h)
        if (1 <= Dim && Dim <= 3 && isFloatingPoint!T)
{

    const T h2 = h * h;

    foreach (it; 0 .. max_iter)
    {
        if (it % norm_iter == 0)
        {
            const auto norm = residual_norm!(T, Dim)(F, U, h);
            if (norm <= eps)
            {
                it.writeln;
                break;
            }

        }
        // rote Halbiteration
        sweep!(T, Dim)(Color.red, F, U, h2);
        // schwarze Halbiteration
        sweep!(T, Dim)(Color.black, F, U, h2);
    }

    return U;
}

/++
This is a sweep implementation for 1D
+/
void sweep(T, size_t Dim : 1)(in Color color, const Slice!(T*, 1) F, Slice!(T*, 1) U, T h2)
{
    const auto n = F.shape[0];
    for (size_t i = 1u + color; i < n - 1u; i += 2u)
    {
        U[i] = (U[i - 1u] + U[i + 1u] - F[i] * h2) / 2.0;

    }

}

/++
This is a sweep implementation for 2D
+/
void sweep(T, size_t Dim : 2)(in Color color, const Slice!(T*, 2) F, Slice!(T*, 2) U, T h2)
{
    const auto n = F.shape[0];
    const auto m = F.shape[1];
    for (size_t i = 1u; i < n - 1u; i++)
    {
        for (size_t j = 1u; j < m - 1u; j++)
        {
            if ((i + j) % 2 == color)
            {
                U[i, j] = (U[i - 1, j] + U[i + 1, j] + U[i, j - 1] + U[i, j + 1] - h2 * F[i, j]) / 4.0;
            }
        }
    }
}

/++
This is a sweep implementation for 3D
+/
void sweep(T, size_t Dim : 3)(in Color color, const Slice!(T*, 3) F, Slice!(T*, 3) U, T h2)
{
    const auto n = F.shape[0];
    const auto m = F.shape[1];
    const auto l = F.shape[1];
    for (size_t i = 1u; i < n - 1u; i++)
    {
        for (size_t j = 1u; j < m - 1u; j++)
        {
            for (size_t k = 1u; k < l - 1u; k++)
            {
                if ((i + j) % 2 == color)
                {
                    U[i, j, k] = (U[i - 1, j, k] + U[i + 1, j, k] + U[i, j - 1,
                            k] + U[i, j + 1, k] + U[i, j, k - 1] + U[i, j, k + 1] - h2 * F[i, j, k]) / 4.0;

                }
            }
        }
    }
}

/++
    Computes the L2 norm of the residual
+/
T residual_norm(T, size_t Dim)(Slice!(T*, Dim) F, Slice!(T*, Dim) U, T h)
{
    import mir.math.sum : sum;

    T norm;
    static if (Dim == 1)
    {
        norm = (F - apply_poisson!(T, Dim)(U, h))[1 .. $ - 1].map!(x => x * x).sum;
    }
    else static if (Dim == 2)
    {
        norm = (F - apply_poisson!(T, Dim)(U, h))[1 .. $ - 1, 1 .. $ - 1].map!(x => x * x).sum;
    }
    else static if (Dim == 3)
    {
        norm = (F - apply_poisson!(T, Dim)(U, h))[1 .. $ - 1, 1 .. $ - 1, 1 .. $ - 1].map!(x => x * x)
            .sum;
    }
    import std.math : sqrt;

    return norm.sqrt;

}

unittest
{
    auto U = slice!double([3, 3], 1.0);
    auto F = slice!double([3, 3], 0.0);
    F[1, 1] = 1;

    auto expected = slice!double([3, 3], 1.0);
    expected[1, 1] = 0.75;
    GS_RB!(double, 2, 1)(F, U, 1.0);
    assert(expected == U);

}
