from __future__ import annotations

import importlib.util
import io
import pathlib
import tarfile
import tempfile
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
VALIDATOR_PATH = REPO_ROOT / "deploy" / "scripts" / "state-bundle-validate.py"
SPEC = importlib.util.spec_from_file_location("state_bundle_validate", VALIDATOR_PATH)
validator = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(validator)


def add_file(archive: tarfile.TarFile, name: str, text: str) -> None:
    payload = text.encode("utf-8")
    info = tarfile.TarInfo(name)
    info.size = len(payload)
    archive.addfile(info, io.BytesIO(payload))


def add_dir(archive: tarfile.TarFile, name: str) -> None:
    info = tarfile.TarInfo(name)
    info.type = tarfile.DIRTYPE
    archive.addfile(info)


def make_bundle(members: list[tuple[str, str | None, bytes | None]]) -> pathlib.Path:
    temp_dir = pathlib.Path(tempfile.mkdtemp())
    bundle = temp_dir / "bundle.tar.gz"
    with tarfile.open(bundle, "w:gz") as archive:
        for name, kind, payload in members:
            if kind == "dir":
                add_dir(archive, name)
            elif kind == "symlink":
                info = tarfile.TarInfo(name)
                info.type = tarfile.SYMTYPE
                info.linkname = "target"
                archive.addfile(info)
            else:
                info = tarfile.TarInfo(name)
                payload = payload or b""
                info.size = len(payload)
                archive.addfile(info, io.BytesIO(payload))
    return bundle


VALID_MANIFEST = b"""schema_version = 1
created_at_utc = "2026-07-25T00:00:00Z"
secrets_included = false
"""


class StateBundleValidationTests(unittest.TestCase):
    def test_accepts_valid_bundle(self) -> None:
        bundle = make_bundle(
            [
                ("vapor-server-state", "dir", None),
                ("vapor-server-state/state", "dir", None),
                ("vapor-server-state/manifest.toml", "file", VALID_MANIFEST),
                ("vapor-server-state/state/docs/current.txt", "file", b"release\n"),
            ]
        )
        validator.validate_bundle(bundle)

    def test_rejects_parent_directory_escape(self) -> None:
        bundle = make_bundle(
            [
                ("vapor-server-state", "dir", None),
                ("vapor-server-state/state", "dir", None),
                ("vapor-server-state/manifest.toml", "file", VALID_MANIFEST),
                ("vapor-server-state/state/../escape", "file", b"bad"),
            ]
        )
        with self.assertRaises(validator.ValidationError):
            validator.validate_bundle(bundle)

    def test_rejects_symlink(self) -> None:
        bundle = make_bundle(
            [
                ("vapor-server-state", "dir", None),
                ("vapor-server-state/state", "dir", None),
                ("vapor-server-state/manifest.toml", "file", VALID_MANIFEST),
                ("vapor-server-state/state/link", "symlink", None),
            ]
        )
        with self.assertRaises(validator.ValidationError):
            validator.validate_bundle(bundle)

    def test_rejects_secret_manifest(self) -> None:
        bundle = make_bundle(
            [
                ("vapor-server-state", "dir", None),
                ("vapor-server-state/state", "dir", None),
                (
                    "vapor-server-state/manifest.toml",
                    "file",
                    b"schema_version = 1\nsecrets_included = true\n",
                ),
            ]
        )
        with self.assertRaises(validator.ValidationError):
            validator.validate_bundle(bundle)


if __name__ == "__main__":
    unittest.main()
