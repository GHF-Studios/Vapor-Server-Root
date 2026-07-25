#!/usr/bin/env python3
"""Validate a Vapor state bundle before restore.

This script intentionally prints only success/failure summaries. It must not
dump archive contents because state bundles can contain user/application data.
"""

from __future__ import annotations

import pathlib
import sys
import tarfile
import tomllib


class ValidationError(RuntimeError):
    pass


def validate_member(member: tarfile.TarInfo) -> None:
    name = member.name
    path = pathlib.PurePosixPath(name)
    if path.is_absolute():
        raise ValidationError("bundle contains an absolute path")
    if ".." in path.parts:
        raise ValidationError("bundle contains a parent-directory path component")
    if not path.parts or path.parts[0] != "vapor-server-state":
        raise ValidationError("bundle contains an entry outside vapor-server-state/")
    if member.issym() or member.islnk():
        raise ValidationError("bundle contains a link entry")
    if member.isdev() or member.isfifo():
        raise ValidationError("bundle contains a special-file entry")
    if not (member.isdir() or member.isfile()):
        raise ValidationError("bundle contains an unsupported entry type")


def validate_manifest_text(text: str) -> None:
    try:
        manifest = tomllib.loads(text)
    except tomllib.TOMLDecodeError as error:
        raise ValidationError("bundle manifest is not valid TOML") from error

    if manifest.get("schema_version") != 1:
        raise ValidationError("bundle manifest has unsupported schema_version")
    if manifest.get("secrets_included") is not False:
        raise ValidationError("bundle manifest does not assert secrets_included = false")


def validate_bundle(path: pathlib.Path) -> None:
    if not path.is_file():
        raise ValidationError("bundle path is not a file")

    names: set[str] = set()
    manifest_member: tarfile.TarInfo | None = None
    saw_state = False

    try:
        with tarfile.open(path, "r:gz") as archive:
            for member in archive:
                validate_member(member)
                if member.name in names:
                    raise ValidationError("bundle contains a duplicate archive entry")
                names.add(member.name)
                if member.name == "vapor-server-state/manifest.toml":
                    manifest_member = member
                if member.name == "vapor-server-state/state" or member.name.startswith(
                    "vapor-server-state/state/"
                ):
                    saw_state = True

            if manifest_member is None:
                raise ValidationError("bundle is missing vapor-server-state/manifest.toml")
            if not saw_state:
                raise ValidationError("bundle is missing vapor-server-state/state/")

            manifest_file = archive.extractfile(manifest_member)
            if manifest_file is None:
                raise ValidationError("bundle manifest cannot be read")
            validate_manifest_text(manifest_file.read().decode("utf-8", errors="replace"))
    except tarfile.TarError as error:
        raise ValidationError("bundle is not a readable gzip tar archive") from error


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: state-bundle-validate.py BUNDLE", file=sys.stderr)
        return 2
    try:
        validate_bundle(pathlib.Path(argv[1]))
    except ValidationError as error:
        print(f"state-bundle-validate: {error}", file=sys.stderr)
        return 1
    print("state-bundle-validate: bundle structure is valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
