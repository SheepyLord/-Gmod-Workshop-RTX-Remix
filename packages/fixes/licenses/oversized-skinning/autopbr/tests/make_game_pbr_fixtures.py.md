# make_game_pbr_fixtures.py

GPL-2.0. Generate an 8x8 two-material PMX, four 8x8 maps and a 16x16 coloured,
fully transparent packed PNG for game_pbr_test.cpp. The latter checks straight-alpha
downsampling and conversion at the normal map's smaller size.
A 7x7 two-colour PNG checks exact fractional area weights and independent alpha at 3x3.
Run `python tests/make_game_pbr_fixtures.py <scratch-under-out>`. Uses only Python's standard
library. Writes synthetic files below the given scratch folder; overwrites only these fixtures.
Exit 0 on success, nonzero on filesystem/encoding failure. No game or network access.
