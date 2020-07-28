import numpy as np
from abc import abstractmethod
from ..GaussSeidel.GaussSeidel_RB import GS_RB
from ..GaussSeidel.GaussSeidel import gauss_seidel
from ..tools.operators import poisson_operator_like
from ..tools.apply_poisson import apply_poisson

from .restriction import restriction, weighted_restriction
from .prolongation import prolongation


class AbstractCycle:
    def __init__(self, F, v1, v2, mu, l):
        self.v1 = v1
        self.v2 = v2
        self.mu = mu
        self.F = F
        self.l = l
        self.eps = 1e-30
        self.h = 1 / F.shape[0]
        # ceck if l is plausible
        if np.log2(self.F.shape[0]) < self.l:
            raise ValueError('false value of levels')

    def __call__(self, U, h=None):
        return self.do_cycle(self.F, U, self.l, h)

    @abstractmethod
    def _presmooth(self, F, U, h):
        pass

    @abstractmethod
    def _postsmooth(self, F, U, h):
        pass

    @abstractmethod
    def _compute_residual(self, F, U, h):
        pass

    @abstractmethod
    def _solve(self, F, U, h):
        pass

    @abstractmethod
    def norm(self, U):
        pass

    def _residual(self, U):
        return self._compute_residual(self.F, U, self.h)

    def _compute_correction(self, r, l, h):
        e = np.zeros_like(r)
        for _ in range(self.mu):
            e = self.do_cycle(r.copy(), e, l, h)
        return e

    def do_cycle(self, F, U, l, h=None):
        if h is None:
            h = 1 / U.shape[0]

        if l <= 1 or U.shape[0] <= 1:
            return self._solve(F, U, h)

        U = self._presmooth(F=F, U=U, h=h)

        r = self._compute_residual(F=F, U=U, h=2 * h)

        r = restriction(r)

        e = self._compute_correction(r, l - 1, 2 * h)

        e = prolongation(e, U.shape)

        # correction
        U = U + e

        return self._postsmooth(F=F, U=U, h=h)


class PoissonCycle(AbstractCycle):
    def __init__(self, F, v1, v2, mu, l):
        super().__init__(F, v1, v2, mu, l)

    def _presmooth(self, F, U, h=None):
        return GS_RB(F, U=U, h=h, max_iter=self.v1, eps=self.eps)

    def _postsmooth(self, F, U, h=None):
        return GS_RB(F, U=U, h=h, max_iter=self.v2, eps=self.eps)

    def _compute_residual(self, F, U, h):
        return F - apply_poisson(U, h)

    def _solve(self, F, U, h):
        return GS_RB(F=F, U=U, h=h, max_iter=5_000, eps=1e-3)

    def norm(self, U):
        residual = self._residual(U)
        return np.linalg.norm(residual[1:-1, 1:-1])


class GeneralCycle(AbstractCycle):
    def __init__(self, A, F, v1, v2, mu, l):
        super().__init__(F, v1, v2, mu, l)
        self.curl = self.l
        # self.A is Array of As for each level
        self.A = [None] * self.l
        # save As with respect to the corresponding level at index of that level
        self.A[self.l - 1] = A
        for level in range(self.l - 1, 0, -1):
            self.A[level-1] = weighted_restriction(self.A[level])

    def _presmooth(self, F, U, h=None):
        return gauss_seidel(self.A[self.curl - 1], F, U, max_iter=self.v1)

    def _postsmooth(self, F, U, h=None):
        self.curl += 1
        return gauss_seidel(self.A[self.curl - 1], F, U, max_iter=self.v2)

    def _compute_residual(self, F, U, h):
        return F - (self.A[self.curl - 1] @ U)

    def _solve(self, F, U, h):
        return np.linalg.solve(self.A[self.curl - 1], F)

    def norm(self, U):
        residual = self._residual(U)
        return np.linalg.norm(residual)

    def do_cycle(self, F, U, l, h=None):
        self.curl = l
        return super().do_cycle(F, U, l, h)