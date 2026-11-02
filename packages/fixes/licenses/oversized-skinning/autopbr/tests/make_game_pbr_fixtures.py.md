# make_game_pbr_fixtures.py

GPL-2.0. Generate an 8x8 two-material PMX and four tiny PNGs for game_pbr_test.cpp.
Run `python tests/make_game_pbr_fixtures.py <scratch-under-out>`. Uses only Python's standard
library. Writes synthetic files below the given scratch folder; overwrites only these fixtures.
Exit 0 on success, nonzero on filesystem/encoding failure. No game or network access.
