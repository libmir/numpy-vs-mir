import numpy as np
from ..GaussSeidel.GaussSeidel_RB import GS_RB
from ..GaussSeidel.GaussSeidel import gauss_seidel
from ..tools.operators import poisson_operator_like
from ..tools.apply_poisson import apply_poisson

from .restriction import restriction
from .prolongation import prolongation


class Cycle:
    def __init__(self, v1, v2, mu):
        self.v1 = v1
        self.v2 = v2
        self.mu = mu

    def __call__(self, F, U, l, h=None):
        return self.do_cycle(F, U, l, h)

    def _presmooth(self, F, U, h=None):
        return GS_RB(F, U=U, max_iter=self.v1)

    def _postsmooth(self, F, U, h=None):
        return GS_RB(F, U=U, max_iter=self.v2)

    def do_cycle(self, F, U, l, h=None):
        if h is None:
            h = 1 / U.shape[0]

        if l <= 1 or U.shape[0] <= 1:
            # solve
            return GS_RB(F, U=U, h=h, max_iter=5000)
        # smoothing
        U = GS_RB(F, U=U, max_iter=self.v1)
        # residual
        r = F - apply_poisson(U, 2 * h)
        # restriction
        r = restriction(r)

        # recursive call
        e = np.zeros_like(r)
        for _ in range(self.mu):
            e = self.do_cycle(np.copy(r), e, l - 1, 2 * h)

        # prolongation
        e = prolongation(e, U.shape)

        # correction
        U = U + e

        # post smoothing
        return GS_RB(F, U=U, h=h, max_iter=self.v2)
