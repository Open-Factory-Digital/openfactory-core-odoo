"""Cheap checks on the files a change touches — no Odoo, no database, stdlib only.

    git diff --name-only <base> | python odoo_lint.py <series>      (paths relative to the cwd)

Errors (exit 1): Python that does not compile, XML that does not parse, a CSV that does not read,
a __manifest__.py that is not a literal dict or lacks `name`, an access file of the wrong kind for
the series or without its header columns. Warnings (exit 0): a manifest version that does not
start with the series, no `license` (or, from 20.0, no `author`), a new `_name` model with no
access rule.

Access rules changed shape in 20.0: `ir.model.access` (and `ir.rule`) became `ir.access`, declared
in `security/ir.access.csv` with the header `id,name,model_id,group_id/id,operation,domain`, where
`model_id` is the model's technical name and `operation` a subset of `crud` (`r`, `cru`, …). An
`ir.model.access.csv` in a 20.0 module stops the module from loading (KeyError 'ir.model.access').
"""

from __future__ import annotations

import ast
import csv
import itertools
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

LEGACY_FILE = "ir.model.access.csv"   # up to 19.0
LEGACY_HEADER = {"id", "name", "model_id:id", "group_id:id",
                 "perm_read", "perm_write", "perm_create", "perm_unlink"}
ACCESS_FILE = "ir.access.csv"         # 20.0 on
ACCESS_HEADER = {"id", "name", "model_id", "operation"}
ACCESS_FROM = 20
# `ir.access.operation`'s selection: the non-empty subsets of c, r, u, d, in that order
OPERATIONS = {"".join(c for c, keep in zip("crud", bits) if keep)
              for bits in itertools.product((0, 1), repeat=4)} - {""}


def major(series: str) -> int:
    """20 for '20.0'; 0 when unknown (then both access files are accepted)."""
    m = re.match(r"(\d+)", series)
    return int(m.group(1)) if m else 0


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
                if p.name in (LEGACY_FILE, ACCESS_FILE):
                    check_access_file(p, rows, major(series), errors)
        except (ET.ParseError, csv.Error, UnicodeDecodeError) as exc:  # (ParseError is a SyntaxError)
            errors.append(f"{p}: {exc}")
        except SyntaxError as exc:
            errors.append(f"{p}:{exc.lineno}: {exc.msg}")
    for root in sorted(modules):
        check_access_rules(root, major(series), warnings)
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
    if major(series) >= ACCESS_FROM and "author" not in data:
        warnings.append(f"{p}: no 'author' (Odoo {series} warns on every load)")
    if not isinstance(data.get("depends", []), list):
        errors.append(f"{p}: 'depends' must be a list")


def _strip_comments(src: str) -> str:
    # literal_eval needs the expression alone: drop the leading comment/encoding lines
    return re.sub(r"^\s*#.*$", "", src, flags=re.M).strip()


def check_access_file(p: Path, rows: list[list[str]], series_major: int, errors: list[str]) -> None:
    if p.name == LEGACY_FILE:
        if series_major >= ACCESS_FROM:
            errors.append(f"{p}: there is no ir.model.access from {ACCESS_FROM}.0 on — the module "
                          f"will not load; declare the rules in security/{ACCESS_FILE} "
                          f"(id,name,model_id,group_id/id,operation,domain)")
            return
        expected = LEGACY_HEADER
    else:
        if series_major and series_major < ACCESS_FROM:
            errors.append(f"{p}: ir.access exists from {ACCESS_FROM}.0 on — on this series the "
                          f"rules go in security/{LEGACY_FILE}")
            return
        expected = ACCESS_HEADER
    header = rows[0] if rows else []
    if not expected <= set(header):
        errors.append(f"{p}: header must include {sorted(expected)}")
        return
    if p.name == ACCESS_FILE:
        col = header.index("operation")
        for n, row in enumerate(rows[1:], start=2):
            if row and (len(row) <= col or row[col] not in OPERATIONS):
                op = row[col] if len(row) > col else ""
                errors.append(f"{p}:{n}: operation {op!r} — a subset of 'crud' in that order "
                              f"('r', 'cru', 'crud', …)")


def check_access_rules(root: Path, series_major: int, warnings: list[str]) -> None:
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
                if isinstance(inherit, ast.Constant):
                    inherits = {inherit.value}
                elif isinstance(inherit, (ast.List, ast.Tuple)):
                    inherits = {e.value for e in inherit.elts if isinstance(e, ast.Constant)}
                else:
                    inherits = set()
                if name.value not in inherits and not _truthy(abstract) \
                        and not any(isinstance(b, ast.Attribute) and b.attr == "AbstractModel"
                                    for b in node.bases):
                    new_models.add(name.value)
    if not new_models:
        return
    current = series_major >= ACCESS_FROM or (
        not series_major and (root / "security" / ACCESS_FILE).is_file())
    access = root / "security" / (ACCESS_FILE if current else LEGACY_FILE)
    if not access.is_file():
        warnings.append(f"{root}: defines {sorted(new_models)} but has no "
                        f"security/{access.name} (users will get access errors)")
        return
    try:
        with access.open(newline="", encoding="utf-8") as fh:
            rows = list(csv.reader(fh))
    except (csv.Error, UnicodeDecodeError):
        return  # reported as an error above
    if current:  # model_id is the technical name
        col = rows[0].index("model_id") if rows and "model_id" in rows[0] else None
        named = {r[col] for r in rows[1:] if col is not None and len(r) > col}
    else:        # model_id:id is the model's XML id
        text = access.read_text(encoding="utf-8")
        named = {m for m in new_models if f"model_{m.replace('.', '_')}" in text}
    for model in sorted(new_models - named):
        warnings.append(f"{access}: no rule for model {model!r}")


def _truthy(node: ast.AST | None) -> bool:
    return isinstance(node, ast.Constant) and bool(node.value)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else ""))
