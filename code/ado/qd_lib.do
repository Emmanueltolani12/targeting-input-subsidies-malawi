*==============================================================================
* qd_lib.do -- QUAIDS with demographic/quota translation, control-function
* residual and Shonkwiler-Yen censoring (the demand system of steps 13-15).
*
* Share equation of good i (n goods, n-1 free under latent adding-up):
*   w*_i = alpha_i(z) + sum_j g_ij ln p_j + b_i x + l_i/b(p) x^2 + t_i v
*   alpha_i(z) = a_i + sum_q e_iq z_q     (z: demographics and quotas q_k)
*   x = ln m - ln a(p),  ln a(p) = a0 + sum_i alpha_i(z) ln p_i
*                                   + 1/2 sum_i sum_j g_ij ln p_i ln p_j
*   b(p) = prod p_i^b_i
*   censored system: w_i = Phi_i w*_i + d_i phi_i
* Restrictions: homogeneity and symmetry of the price terms; adding-up of
* a, b, l, e when QD_free = 0 (uncensored first stage). With QD_free = 1
* (censored second stage) a, b, l, e are free in all n equations.
*
* Parameter vector (in this order; m = n-1, or n when QD_free = 1):
*   a_1..a_m, b_1..b_m, l_1..l_m, g_ij (lower triangle of goods 1..n-1,
*   row-wise), e_iq (i=1..m, q=1..Q), t_1..t_neq, d_1..d_neq
*
* The nlsur evaluator reads its settings from globals:
*   QD_n QD_neq QD_Q QD_cf(0/1) QD_cens(0/1) QD_a0
*==============================================================================

foreach f in qd_unpack qd_core qd_nlsur qd_elast qd_elast_dm qd_elast_cov qd_save_matrix qd_read_matrix qd_mvn_draw {
	capture mata: mata drop `f'()
}
capture program drop nlsurqd
program define nlsurqd
	version 18
	syntax varlist if, at(name)
	tempvar touse
	mark `touse' `if'
	mata: qd_nlsur("`varlist'", "`touse'", "`at'")
end

mata:
mata set matastrict off

// unpack the parameter vector into full (n-good) matrices
void qd_unpack(real rowvector at, real scalar n, real scalar neq, real scalar Q,
	real scalar cf, real scalar cens,
	a, b, l, G, E, t, d)
{
	real scalar m, pos, i, j, free, ma
	// QD_free = 1: intercepts, expenditure, quadratic and translation terms
	// free in all n equations (censored systems do not add up); price
	// terms keep homogeneity and symmetry
	free = strtoreal(st_global("QD_free"))
	if (free == .) free = 0
	m = n - 1
	ma = (free ? n : m)
	pos = 1
	a = at[pos..pos+ma-1]
	pos = pos + ma
	b = at[pos..pos+ma-1]
	pos = pos + ma
	l = at[pos..pos+ma-1]
	pos = pos + ma
	G = J(n, n, 0)
	for (i = 1; i <= m; i++) {
		for (j = 1; j <= i; j++) {
			G[i, j] = at[pos]
			G[j, i] = at[pos]
			pos = pos + 1
		}
	}
	for (i = 1; i <= m; i++) G[i, n] = -sum(G[i, 1..m])
	G[n, 1..m] = G[1..m, n]'
	G[n, n] = -sum(G[1..m, n])
	E = J(n, Q, 0)
	if (Q > 0) {
		for (i = 1; i <= ma; i++) {
			E[i, .] = at[pos..pos+Q-1]
			pos = pos + Q
		}
		if (!free) E[n, .] = -colsum(E[1..m, .])
	}
	if (!free) {
		a = a, 1 - sum(a)
		b = b, -sum(b)
		l = l, -sum(l)
	}
	t = J(1, neq, 0)
	d = J(1, neq, 0)
	if (cf) {
		t = at[pos..pos+neq-1]
		pos = pos + neq
	}
	if (cens) {
		d = at[pos..pos+neq-1]
		pos = pos + neq
	}
}

// latent shares and the pieces needed for elasticities
void qd_core(real rowvector at, real scalar n, real scalar neq, real scalar Q,
	real scalar cf, real scalar cens, real scalar a0,
	real matrix lnp, real colvector lnm, real matrix Z, real colvector v,
	W, x, B, AH)
{
	real rowvector a, b, l, t, d
	real matrix G, E
	real colvector lna
	qd_unpack(at, n, neq, Q, cf, cens, a, b, l, G, E, t, d)
	AH = J(rows(lnp), 1, a)
	if (Q > 0) AH = AH + Z * E'
	lna = a0 :+ rowsum(AH :* lnp) + 0.5 * rowsum((lnp * G) :* lnp)
	B = exp(lnp * b')
	x = lnm - lna
	W = AH + lnp * G + x * b + ((x:^2) :/ B) * l
	if (cf) W[., 1..neq] = W[., 1..neq] + v * t
}

void qd_nlsur(string scalar vl, string scalar tu, string scalar atn)
{
	real scalar n, neq, Q, cf, cens, a0, c
	real matrix X, lnp, Z, Phi, phi, W, x, B, AH
	real colvector lnm, v
	real rowvector at, a, b, l, t, d
	real matrix G, E
	n = strtoreal(st_global("QD_n"))
	neq = strtoreal(st_global("QD_neq"))
	Q = strtoreal(st_global("QD_Q"))
	cf = strtoreal(st_global("QD_cf"))
	cens = strtoreal(st_global("QD_cens"))
	a0 = strtoreal(st_global("QD_a0"))
	at = st_matrix(atn)
	st_view(X, ., tokens(vl), tu)
	c = neq
	lnp = X[., c+1..c+n]
	c = c + n
	lnm = X[., c+1]
	c = c + 1
	if (Q > 0) {
		Z = X[., c+1..c+Q]
		c = c + Q
	}
	else Z = J(rows(X), 0, 0)
	if (cf) {
		v = X[., c+1]
		c = c + 1
	}
	else v = J(rows(X), 1, 0)
	qd_core(at, n, neq, Q, cf, cens, a0, lnp, lnm, Z, v, W, x, B, AH)
	if (cens) {
		Phi = X[., c+1..c+n]
		c = c + n
		phi = X[., c+1..c+n]
		c = c + n
		qd_unpack(at, n, neq, Q, cf, cens, a, b, l, G, E, t, d)
		W[., 1..neq] = Phi[., 1..neq] :* W[., 1..neq] + phi[., 1..neq] :* d
	}
	X[., 1..neq] = W[., 1..neq]
}

// elasticities at one evaluation point
// pt: lnp (1 x n), lnm, z (1 x Q), Phi (1 x n), phi (1 x n)
// returns rowvector: eta (n), Marshallian e_ij (n x n, row-wise),
//   quota elasticities z_ik (n x K) when K > 0
real rowvector qd_elast(real rowvector at, real scalar n, real scalar neq,
	real scalar Q, real scalar cf, real scalar cens, real scalar a0,
	real rowvector lnp, real scalar lnm, real rowvector z,
	real rowvector Phi, real rowvector phi,
	real scalar K, real rowvector qpos, real rowvector qbar,
	real rowvector pq, real scalar Mbar)
{
	real rowvector a, b, l, t, d, mu0, w, eta, ah, out
	real matrix G, E, W, AH, e, zk
	real scalar x, B, i, j, k
	real colvector xx, BB
	qd_unpack(at, n, neq, Q, cf, cens, a, b, l, G, E, t, d)
	qd_core(at, n, neq, Q, cf, cens, a0, lnp, lnm, z, 0, W, xx, BB, AH)
	x = xx[1]
	B = BB[1]
	ah = AH[1, .]
	w = W[1, .]
	if (cens) w = Phi :* w + phi :* (d, J(1, n - cols(d), 0))
	else Phi = J(1, n, 1)
	mu0 = b + 2 * l * x / B
	eta = (Phi :* mu0) :/ w :+ 1
	e = J(n, n, 0)
	for (i = 1; i <= n; i++) {
		for (j = 1; j <= n; j++) {
			e[i, j] = Phi[i] * (G[i, j] - mu0[i] * (ah[j] + G[j, .] * lnp') - l[i] * b[j] * x^2 / B) / w[i] - (i == j)
		}
	}
	out = eta, vec(e')'
	if (K > 0) {
		zk = J(n, K, 0)
		for (i = 1; i <= n; i++) {
			for (k = 1; k <= K; k++) {
				zk[i, k] = Phi[i] * (E[i, qpos[k]] * qbar[k] / w[i] + b[i] / w[i] * pq[k] / Mbar)
			}
		}
		out = out, vec(zk')'
	}
	return(out)
}

// delta-method standard errors of qd_elast at one point
real matrix qd_elast_dm(real rowvector at, real matrix V, real scalar n,
	real scalar neq, real scalar Q, real scalar cf, real scalar cens,
	real scalar a0, real rowvector lnp, real scalar lnm, real rowvector z,
	real rowvector Phi, real rowvector phi, real scalar K,
	real rowvector qpos, real rowvector qbar, real rowvector pq, real scalar Mbar)
{
	real rowvector g0, gp, gm, h
	real matrix Jm
	real scalar p, eps
	g0 = qd_elast(at, n, neq, Q, cf, cens, a0, lnp, lnm, z, Phi, phi, K, qpos, qbar, pq, Mbar)
	Jm = J(cols(g0), cols(at), 0)
	for (p = 1; p <= cols(at); p++) {
		eps = 1e-6 * max((1, abs(at[p])))
		h = J(1, cols(at), 0)
		h[p] = eps
		gp = qd_elast(at + h, n, neq, Q, cf, cens, a0, lnp, lnm, z, Phi, phi, K, qpos, qbar, pq, Mbar)
		gm = qd_elast(at - h, n, neq, Q, cf, cens, a0, lnp, lnm, z, Phi, phi, K, qpos, qbar, pq, Mbar)
		Jm[., p] = (gp - gm)' / (2 * eps)
	}
	return((g0 \ sqrt(diagonal(Jm * V * Jm'))'))
}

// elasticities and their full delta-method covariance at one point:
// returns (g0 \ J V J'), i.e. (1 + k) x k; used for parametric draws of the
// elasticities in the bootstrap of the structural simulations
real matrix qd_elast_cov(real rowvector at, real matrix V, real scalar n,
	real scalar neq, real scalar Q, real scalar cf, real scalar cens,
	real scalar a0, real rowvector lnp, real scalar lnm, real rowvector z,
	real rowvector Phi, real rowvector phi, real scalar K,
	real rowvector qpos, real rowvector qbar, real rowvector pq, real scalar Mbar)
{
	real rowvector g0, gp, gm, h
	real matrix Jm
	real scalar p, eps
	g0 = qd_elast(at, n, neq, Q, cf, cens, a0, lnp, lnm, z, Phi, phi, K, qpos, qbar, pq, Mbar)
	Jm = J(cols(g0), cols(at), 0)
	for (p = 1; p <= cols(at); p++) {
		eps = 1e-6 * max((1, abs(at[p])))
		h = J(1, cols(at), 0)
		h[p] = eps
		gp = qd_elast(at + h, n, neq, Q, cf, cens, a0, lnp, lnm, z, Phi, phi, K, qpos, qbar, pq, Mbar)
		gm = qd_elast(at - h, n, neq, Q, cf, cens, a0, lnp, lnm, z, Phi, phi, K, qpos, qbar, pq, Mbar)
		Jm[., p] = (gp - gm)' / (2 * eps)
	}
	return((g0 \ Jm * V * Jm'))
}

// save a matrix to a Mata file
void qd_save_matrix(string scalar fn, real matrix X)
{
	real scalar fh
	if (fileexists(fn)) unlink(fn)
	fh = fopen(fn, "w")
	fputmatrix(fh, X)
	fclose(fh)
}

// read a matrix saved by qd_save_matrix
real matrix qd_read_matrix(string scalar fn)
{
	real scalar fh
	real matrix X
	fh = fopen(fn, "r")
	X = fgetmatrix(fh)
	fclose(fh)
	return(X)
}

// one draw from N(m, C) with a possibly singular covariance (eigen root)
real rowvector qd_mvn_draw(real rowvector m, real matrix C)
{
	real matrix X
	real rowvector L
	symeigensystem((C + C') / 2, X, L)
	L = L :* (L :> 0)
	return(m + (X * diag(sqrt(L)) * rnormal(cols(m), 1, 0, 1))')
}
end
