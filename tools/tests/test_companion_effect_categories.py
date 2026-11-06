"""Include the companion's transient effect observer scenarios in tools/test.ps1."""
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "companion/tests"))
from test_effect_categories import EffectCategoryTests  # noqa: E402, F401
