#!/usr/bin/env python3
"""Validate env-setup JSON files against their published schemas."""

from __future__ import annotations

import json
import pathlib
import sys

from jsonschema import Draft202012Validator, FormatChecker

ROOT = pathlib.Path(__file__).resolve().parents[1]


def load_json(path: pathlib.Path) -> object:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def validate(instance_path: pathlib.Path, schema_path: pathlib.Path) -> list[str]:
    instance = load_json(instance_path)
    schema = load_json(schema_path)
    validator = Draft202012Validator(schema, format_checker=FormatChecker())
    errors = sorted(validator.iter_errors(instance), key=lambda error: list(error.absolute_path))
    return [
        f"{instance_path.relative_to(ROOT)}:{'.'.join(map(str, error.absolute_path)) or '<root>'}: {error.message}"
        for error in errors
    ]


failures: list[str] = []
plan_schema = ROOT / "schemas" / "setup-plan.schema.json"
for profile in sorted((ROOT / "profiles").glob("*.json")):
    failures.extend(validate(profile, plan_schema))

failures.extend(
    validate(
        ROOT / "release-manifest.json",
        ROOT / "schemas" / "release-manifest.schema.json",
    )
)

if failures:
    print("JSON Schema validation failed:", file=sys.stderr)
    print("\n".join(failures), file=sys.stderr)
    raise SystemExit(1)

print("JSON Schema validation passed.")
