# nightsky_mapping.py

Derives the analytic UV mappings of Night Sky HD LE's sky dome (`stars.nif`) and checks them against
every vertex of the mesh: the constants the runtime's shader uses in `evalStarMap`
(`atmosphere_sky.slangh`, [runtime/patches](../../runtime/README.md) 0004;
[RESEARCH.md](../../docs/RESEARCH.md) section 29).

```powershell
python -I tools\sky\nightsky_mapping.py out\sky\stars_nif.json
```

The input is `stars.nif` as [`nif_read.py`](nif_read.py.md) writes it. It prints, for the three layers:

- **stars** (shape 2): the hemisphere centre `c`, the axes of theta 0 and 90 degrees, the UV radius at
  every 10 degrees from `c`, and the worst UV error of `uv = (1 + r cos theta, r sin theta)` (tiled)
  against the mesh;
- **galaxy** (shape 8): the band's axis and along-axes, `u0`, and the UV error of the band mapping (40
  degrees each side of the great circle);
- **nebula** (shape 11): the UV error of the longitude/latitude mapping, away from the poles.

**Needs:** numpy. **Exit:** 0.
