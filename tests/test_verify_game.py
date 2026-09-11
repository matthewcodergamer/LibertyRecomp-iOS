from __future__ import annotations

import hashlib
import importlib.util
import json
import tempfile
import unittest
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("verify_game", ROOT / "scripts" / "verify-game.py")
verify_game = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
sys.modules[SPEC.name] = verify_game
SPEC.loader.exec_module(verify_game)


class VerifyGameTests(unittest.TestCase):
    def make_game(self, root: Path, xex_bytes: bytes = b"dummy-xex") -> str:
        (root / "default.xex").write_bytes(xex_bytes)
        (root / "common.rpf").write_bytes(b"common")
        (root / "xbox360.rpf").write_bytes(b"xbox")
        (root / "audio.rpf").write_bytes(b"audio")
        return hashlib.sha256(xex_bytes).hexdigest()

    def manifest(self, sha: str | None = None) -> dict:
        revisions = [] if sha is None else [{"id": "test-revision", "xexSha256": sha}]
        return {"schemaVersion": 1, "requiredFiles": [{"path": "default.xex"}, {"path": "common.rpf"}, {"path": "xbox360.rpf"}, {"path": "audio.rpf"}], "supportedRevisions": revisions}

    def test_supported_revision_passes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            sha = self.make_game(root)
            result, code = verify_game.verify_game(root, self.manifest(sha))
            self.assertEqual(code, verify_game.EXIT_OK)
            self.assertTrue(result.ok)
            self.assertTrue(result.supported)
            self.assertEqual(result.matched_revision_id, "test-revision")

    def test_unknown_revision_is_rejected_by_default(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.make_game(root)
            result, code = verify_game.verify_game(root, self.manifest())
            self.assertEqual(code, verify_game.EXIT_UNSUPPORTED)
            self.assertFalse(result.ok)
            self.assertFalse(result.supported)

    def test_unknown_revision_can_be_explicitly_allowed_for_development(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.make_game(root)
            result, code = verify_game.verify_game(root, self.manifest(), allow_unpinned=True)
            self.assertEqual(code, verify_game.EXIT_OK)
            self.assertEqual(result.status, "unverified-development-mode")

    def test_missing_file_is_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "default.xex").write_bytes(b"x")
            result, code = verify_game.verify_game(root, self.manifest())
            self.assertEqual(code, verify_game.EXIT_MISSING)
            self.assertIn("common.rpf", result.missing_files)

    def test_manifest_loader_rejects_wrong_schema(self):
        with tempfile.TemporaryDirectory() as tmp:
            manifest_path = Path(tmp) / "manifest.json"
            manifest_path.write_text(json.dumps({"schemaVersion": 99, "requiredFiles": [], "supportedRevisions": []}))
            with self.assertRaises(ValueError):
                verify_game.load_manifest(manifest_path)


if __name__ == "__main__":
    unittest.main()
