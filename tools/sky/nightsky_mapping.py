"""The analytic UV mappings of NightSky HD LE's star dome (stars.nif), checked
against every vertex of the mesh. Prints the constants atmosphere_sky.slangh uses.
Usage: python -I tools/sky/nightsky_mapping.py <stars_nif.json>"""
import json
import sys

import numpy as np

info = json.load(open(sys.argv[1]))


def shape(idx):
    b = info['blocks'][idx]
    v = np.array(b['v']).reshape(-1, 3)
    return v / np.linalg.norm(v, axis=1, keepdims=True), np.array(b['uv']).reshape(-1, 2)


def wrap_err(a, b):
    """Distance between UVs modulo whole tiles."""
    d = a - b
    return np.abs(d - np.round(d))


# --- Stars: two hemispheres, each an azimuthal layout about its centre, tiled. ---
d, uv = shape(2)
rho = np.hypot(uv[:, 0] - 1.0, uv[:, 1])
c = d[(rho < 1e-3) & (d[:, 2] > 0)][0]
up = d @ c >= -1e-6
alpha = np.degrees(np.arccos(np.clip(np.where(up, 1, -1) * (d @ c), -1, 1)))
theta = np.arctan2(uv[:, 1], uv[:, 0] - 1.0)
# e1 points at theta 0, e2 at theta 90 degrees, both tangent at c.
q = np.where(up[:, None], d, -d)
t = q - np.outer(q @ c, c)
sel = (np.abs(theta) < 1e-3) & (rho > 0.1) & (alpha < 85)
e1 = t[sel].mean(axis=0); e1 /= np.linalg.norm(e1)
sel = (np.abs(theta - np.pi / 2) < 1e-3) & (rho > 0.1) & (alpha < 85)
e2 = t[sel].mean(axis=0); e2 -= e1 * (e2 @ e1); e2 /= np.linalg.norm(e2)
rings = []
for k in range(0, 10):
    s = np.abs(alpha - 10 * k) < 0.5
    rings.append(float(rho[s].mean()) if s.any() else None)
print('stars: c', c.round(6).tolist(), 'e1', e1.round(6).tolist(), 'e2', e2.round(6).tolist(), 'cross(c,e1)', np.cross(c, e1).round(4).tolist())
print('  rho at 0..90 deg in 10 deg steps:', [round(r, 5) for r in rings])


def star_uv(q):
    s = np.where(q @ c < 0, -1.0, 1.0)
    q = q * s[:, None]
    a = np.degrees(np.arccos(np.clip(q @ c, -1, 1)))
    r = np.interp(a, np.arange(0, 100, 10), rings)
    th = np.arctan2(q @ e2, q @ e1)
    return np.stack([1 + r * np.cos(th), r * np.sin(th)], axis=1)


err = wrap_err(star_uv(d), uv)
print('  analytic vs mesh UV error (tiles): max', err.max().round(5), 'p99', np.percentile(err, 99).round(5))

# --- Galaxy: a band 40 degrees each side of a great circle. ---
d, uv = shape(8)
mid = d[np.abs(uv[:, 1] - 0.5) < 1e-3]
n = np.linalg.svd(mid)[2][2]
if (d[np.argmin(uv[:, 1])] @ n) < 0:
    n = -n  # v = 0 on the +n side
b0 = mid[np.argmin(np.abs(uv[np.abs(uv[:, 1] - 0.5) < 1e-3, 0] - np.round(uv[np.abs(uv[:, 1] - 0.5) < 1e-3, 0])))]
b0 = b0 - n * (b0 @ n); b0 /= np.linalg.norm(b0)
cb = np.cross(n, b0)
along = np.arctan2(d @ cb, d @ b0)
u0 = uv[np.abs(uv[:, 1] - 0.5) < 1e-3][np.argmin(np.abs(np.arctan2(mid @ cb, mid @ b0)))][0]
beta = np.arcsin(np.clip(d @ n, -1, 1))
half = np.radians(40.0)
g_uv = np.stack([u0 + along / (2 * np.pi / 3), 0.5 - 0.5 * np.sin(beta) / np.sin(half)], axis=1)
err = wrap_err(g_uv, uv)
print('galaxy: n', n.round(6).tolist(), 'b', b0.round(6).tolist(), 'c', cb.round(6).tolist(), 'u0', round(float(u0), 5))
print('  analytic vs mesh UV error: u max', err[:, 0].max().round(5), 'v max', np.abs(g_uv[:, 1] - uv[:, 1]).max().round(5))

# --- Nebula: longitude / latitude. ---
d, uv = shape(11)
lon = np.arctan2(d[:, 1], d[:, 0]); lat = np.arcsin(np.clip(d[:, 2], -1, 1))
n_uv = np.stack([0.5 + lon / (2 * np.pi), 0.5 - lat / np.pi], axis=1)
err = wrap_err(n_uv, uv)
pole = np.abs(np.degrees(lat)) > 89.9  # longitude means nothing at the poles
print('nebula: analytic vs mesh UV error: u max (no poles)', err[~pole, 0].max().round(5), 'v max', np.abs(n_uv[:, 1] - uv[:, 1]).max().round(5))
