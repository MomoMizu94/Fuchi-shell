import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("palette", Path(__file__).parents[1] / "scripts/palette.py")
palette = importlib.util.module_from_spec(spec)
spec.loader.exec_module(palette)


class LightPaletteTest(unittest.TestCase):
    def test_light_text_is_readable_without_darkening_every_color(self):
        original = {
            "wallpaper": "/wallpaper.png",
            "special": {"background": "#eef4f4", "foreground": "#2f3440", "cursor": "#2f3440"},
            "colors": {"color0": "#eef4f4", "color1": "#d97c67", "color2": "#164387",
                       "color3": "#fff299", "color8": "#aabbbb", "color9": "#d97c67"},
        }
        before = copy.deepcopy(original)
        result = palette.light_palette(original)
        self.assertEqual(original, before, "Cached pywal palette must remain unmodified")
        self.assertEqual(result["special"], original["special"])
        self.assertEqual(result["wallpaper"], original["wallpaper"])
        self.assertEqual(result["colors"]["color0"], "#eef4f4")
        self.assertEqual(result["colors"]["color2"], "#164387")
        self.assertEqual(result["colors"]["color1"], result["colors"]["color9"])
        background = palette.shade(result["special"]["background"], 1 / 1.12)
        for key, color in result["colors"].items():
            if key != "color0":
                ratio = (palette.luminance(background) + 0.05) / (palette.luminance(color) + 0.05)
                self.assertGreaterEqual(ratio, 4.5, key)


if __name__ == "__main__":
    unittest.main()
