from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("check_assets", ROOT / "scripts" / "check-prohibited-assets.py")
check_assets = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(check_assets)


class ProhibitedAssetTests(unittest.TestCase):
    def test_safe_text_document_is_allowed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            path = root / "notes.md"
            path.write_text("Documentation may mention default.xex without containing it.")
            self.assertEqual(check_assets.find_violations(root, [path]), [])

    def test_rpf_file_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            path = root / "common.rpf"
            path.write_bytes(b"not real game data")
            violations = check_assets.find_violations(root, [path])
            self.assertTrue(any("common.rpf" in item for item in violations))

    def test_private_key_marker_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            path = root / "secret.txt"
            path.write_text("-----BEGIN PRIVATE KEY-----\nplaceholder")
            violations = check_assets.find_violations(root, [path])
            self.assertTrue(any("private-key" in item for item in violations))


if __name__ == "__main__":
    unittest.main()
