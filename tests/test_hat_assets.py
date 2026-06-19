#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/asset-build"))

from build_master_128 import alpha_pixel_count, nearest_resize, nontransparent_bounds, read_png  # noqa: E402


class HatAssetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source_manifest = json.loads(
            (ROOT / "art/aseprite/hats/hats_manifest.json").read_text(encoding="utf-8")
        )
        cls.hats_dir = ROOT / "pet-runtime/assets/master_128/hats"

    def test_assets_are_128_overlays_inside_head_bounds(self) -> None:
        bounds = self.source_manifest["bounds"]
        allowed = (
            bounds["x"],
            bounds["y"],
            bounds["x"] + bounds["w"] - 1,
            bounds["y"] + bounds["h"] - 1,
        )
        for hat in self.source_manifest["hats"]:
            with self.subTest(hat=hat["id"]):
                image = read_png(self.hats_dir / hat["file"])
                self.assertEqual((image.width, image.height), (128, 128))
                opaque = nontransparent_bounds(image)
                if hat["id"] == "none":
                    self.assertEqual(alpha_pixel_count(image), 0)
                    continue
                self.assertIsNotNone(opaque)
                x0, y0, x1, y1 = opaque
                self.assertGreaterEqual(x0, allowed[0])
                self.assertGreaterEqual(y0, allowed[1])
                self.assertLessEqual(x1, allowed[2])
                self.assertLessEqual(y1, allowed[3])

    def test_requested_menu_hats_are_present(self) -> None:
        menu_ids = [hat["id"] for hat in self.source_manifest["hats"] if hat.get("menu")]
        self.assertEqual(menu_ids, [hat["id"] for hat in self.source_manifest["hats"]])
        self.assertEqual(len(menu_ids), 18)

    def test_anchor_is_two_pixels_above_body_top(self) -> None:
        body = read_png(ROOT / "pet-runtime/assets/master_128/body/teti_track_front_neutral_128.png")
        body_bounds = nontransparent_bounds(body)
        self.assertIsNotNone(body_bounds)
        self.assertEqual(self.source_manifest["anchor"]["x"], 64)
        self.assertEqual(self.source_manifest["anchor"]["y"], body_bounds[1] - 2)

    def test_problem_hats_have_top_padding(self) -> None:
        for hat_id in ("beanie", "antenna", "sprout"):
            with self.subTest(hat=hat_id):
                image = read_png(self.hats_dir / f"hat_{hat_id}_128.png")
                opaque = nontransparent_bounds(image)
                self.assertIsNotNone(opaque)
                self.assertGreaterEqual(opaque[1], 8)
                self.assertLessEqual(opaque[1], 10)

    def test_manifest_uses_only_aseprite_frames(self) -> None:
        master = ROOT / "art/aseprite/hats/teti_track_hat_master.aseprite"
        self.assertTrue(master.is_file())
        for index, hat in enumerate(self.source_manifest["hats"]):
            with self.subTest(hat=hat["id"]):
                self.assertEqual(hat.get("source_frame"), index)
                self.assertNotIn("source_png", hat)
            self.assertNotIn("generator", hat)

    def test_runtime_outputs_contain_only_current_manifest_hats(self) -> None:
        expected = {hat["file"] for hat in self.source_manifest["hats"]}
        actual = {path.name for path in self.hats_dir.glob("hat_*_128.png")}
        self.assertEqual(len(expected), 18)
        self.assertEqual(actual, expected)
        self.assertEqual(
            json.loads((self.hats_dir / "hats_manifest.json").read_text(encoding="utf-8")),
            self.source_manifest,
        )

    def test_deprecated_hat_sources_are_absent(self) -> None:
        self.assertFalse((ROOT / "art/aseprite/hats/debug").exists())

    def test_hats_remain_readable_at_64(self) -> None:
        for hat in self.source_manifest["hats"]:
            if hat["id"] == "none":
                continue
            with self.subTest(hat=hat["id"]):
                image = read_png(self.hats_dir / hat["file"])
                downscaled = nearest_resize(image, 64, 64)
                self.assertGreater(alpha_pixel_count(downscaled), 8)

        preview = read_png(
            ROOT / "pet-runtime/assets/master_128/previews/teti_track_hats_preview_64.png"
        )
        self.assertEqual((preview.width, preview.height), (384, 192))

    def test_generated_runtime_manifest_contains_every_hat(self) -> None:
        runtime_manifest = (ROOT / "pet-runtime/lua/hats_manifest.lua").read_text(encoding="utf-8")
        source_hash = hashlib.sha256(
            (ROOT / "art/aseprite/hats/teti_track_hat_master.aseprite").read_bytes()
        ).hexdigest()
        manifest_hash = hashlib.sha256(
            (ROOT / "art/aseprite/hats/hats_manifest.json").read_bytes()
        ).hexdigest()
        self.assertIn('source = "aseprite_master"', runtime_manifest)
        self.assertIn(f'source_sha256 = "{source_hash}"', runtime_manifest)
        self.assertIn(f'manifest_sha256 = "{manifest_hash}"', runtime_manifest)
        self.assertIn('cache = "fresh"', runtime_manifest)
        self.assertIn('render_layer = "world"', runtime_manifest)
        self.assertIn('transform = "linked_to_body"', runtime_manifest)
        for hat in self.source_manifest["hats"]:
            self.assertIn(f'["{hat["id"]}"]', runtime_manifest)
            self.assertIn(f'asset_key = "hat_{hat["id"]}_128"', runtime_manifest)
            self.assertIn(
                f'file = "pet-runtime/assets/master_128/hats/{hat["file"]}"',
                runtime_manifest,
            )
            self.assertIn(f'source_tag = "{hat["id"]}"', runtime_manifest)
        lowered = runtime_manifest.lower()
        for forbidden in ("debug/", "deprecated/", "fallback/", "codex_png"):
            self.assertNotIn(forbidden, lowered)

    def test_runtime_atlas_matches_production_sheet(self) -> None:
        self.assertEqual(
            (ROOT / "pet-runtime/lua/sprites.png").read_bytes(),
            (ROOT / "pet-runtime/assets/master_128/sheets/teti_track_master_sheet_128.png").read_bytes(),
        )


if __name__ == "__main__":
    unittest.main()
