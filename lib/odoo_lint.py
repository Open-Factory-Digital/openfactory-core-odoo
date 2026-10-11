"""Cheap checks on the files a change touches — no Odoo, no database, stdlib only.

    git diff --name-only <base> | python odoo_lint.py <series>      (paths relative to the cwd)

Errors (exit 1): Python that does not compile, XML that does not parse, a CSV that does not read,
a __manifest__.py that is not a literal dict or lacks `name`, an ir.model.access.csv without its
header columns. Warnings (exit 0): a manifest version that does not start with the series, no
`license`, a new `_name` model in a module with no security/ir.model.access.csv.
"""

from __future__ import annotations

import ast
import csv
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ACCESS_HEADER = {"id", "name", "model_id:id", "group_id:id",
                 "perm_read", "perm_write", "perm_create", "perm_unlink"}


def module_root(path: Path) -> Path | None:
    for parent in path.parents:
        if (parent / "__manifest__.py").is_file():
            return parent
    return None


def main(series: str) -> int:
    errors: list[str] = []
    warnings: list[str] = []
    paths = [Path(line.strip()) for line in sys.stdin if line.strip()]
    modules: set[Path] = set()
    for p in paths:
        if not p.is_file():
            continue  # deleted
        root = module_root(p)
        if root is not None:
            modules.add(root)
        try:
            if p.suffix == ".py":
                src = p.read_text(encoding="utf-8")
                compile(src, str(p), "exec")
                if p.name == "__manifest__.py":
                    check_manifest(p, src, series, errors, warnings)
            elif p.suffix == ".xml":
                ET.parse(p)
            elif p.suffix == ".csv":
                with p.open(newline="", encoding="utf-8") as fh:
                    rows = list(csv.reader(fh))
                if p.name == "ir.model.access.csv":
                    header = set(rows[0]) if rows else set()
                    if not ACCESS_HEADER <= header:
                        errors.append(f"{p}: header must include {sorted(ACCESS_HEADER)}")
        except SyntaxError as exc:
            errors.append(f"{p}:{exc.lineno}: {exc.msg}")
        except (ET.ParseError, csv.Error, UnicodeDecodeError) as exc:
            errors.append(f"{p}: {exc}")
    for root in sorted(modules):
        check_access_rules(root, errors, warnings)
    for w in warnings:
        print(f"warning: {w}")
    for e in errors:
        print(f"error: {e}")
    print(f"lint: {len(paths)} changed path(s), {len(modules)} addon(s), "
          f"{len(errors)} error(s), {len(warnings)} warning(s)")
    return 1 if errors else 0


def check_manifest(p: Path, src: str, series: str, errors: list[str], warnings: list[str]) -> None:
    try:
        data = ast.literal_eval(_strip_comments(src))
    except (ValueError, SyntaxError):
        errors.append(f"{p}: must be a single literal dict")
        return
    if not isinstance(data, dict):
        errors.append(f"{p}: must be a dict")
        return
    if not data.get("name"):
        errors.append(f"{p}: 'name' is required")
    version = str(data.get("version", ""))
    if version and not version.startswith(series + "."):
        warnings.append(f"{p}: version {version!r} — the convention is '{series}.x.y.z'")
    if "license" not in data:
        warnings.append(f"{p}: no 'license' (Odoo defaults to LGPL-3 and warns)")
    if not isinstance(data.get("depends", []), list):
        errors.append(f"{p}: 'depends' must be a list")


def _strip_comments(src: str) -> str:
    # literal_eval needs the expression alone: drop the leading comment/encoding lines
    return re.sub(r"^\s*#.*$", "", src, flags=re.M).strip()


def check_access_rules(root: Path, errors: list[str], warnings: list[str]) -> None:
    """New models (`_name = '...'` without `_inherit` of the same name) need access rules."""
    new_models: set[str] = set()
    for py in root.rglob("*.py"):
        if "tests" in py.parts:
            continue
        try:
            tree = ast.parse(py.read_text(encoding="utf-8"))
        except (SyntaxError, UnicodeDecodeError):
            continue
        for node in ast.walk(tree):
            if not isinstance(node, ast.ClassDef):
                continue
            attrs = {t.id: v for s in node.body if isinstance(s, ast.Assign)
                     for t in s.targets if isinstance(t, ast.Name)
                     for v in [s.value]}
            name = attrs.get("_name")
            abstract = attrs.get("_abstract")  # (transient models need rules too, since 14.0)
            if isinstance(name, ast.Constant) and isinstance(name.value, str):
                inherit = attrs.get("_inherit")
                inherits = ({inherit.value} if isinstance(inherit, ast.Constant) else set())
                if name.value not in inherits and not _truthy(abstract) \
                        and not any(isinstance(b, ast.Attribute) and b.attr == "AbstractModel"
                                    for b in node.bases):
                    new_models.add(name.value)
    if not new_models:
        return
    access = root / "security" / "ir.model.access.csv"
    if not access.is_file():
        warnings.append(f"{root}: defines {sorted(new_models)} but has no "
                        f"security/ir.model.access.csv (users will get access errors)")
        return
    text = access.read_text(encoding="utf-8")
    for model in sorted(new_models):
        if f"model_{model.replace('.', '_')}" not in text:
            warnings.append(f"{access}: no rule for model {model!r}")


def _truthy(node: ast.AST | None) -> bool:
    return isinstance(node, ast.Constant) and bool(node.value)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else ""))
