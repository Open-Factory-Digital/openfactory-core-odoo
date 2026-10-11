"""The manifest's `test_inventory`: every Odoo test in the tree, ONE IDENTIFIER PER LINE, nothing
else on stdout.

    python odoo_test_inventory.py <checkout>

Static — read from the source with `ast`, no Odoo, no database — so it runs in seconds on the
clean tree and on the change alike. An id is `<addon>.<module path>.<Class>.<test_method>`, e.g.
`x_hello.tests.test_greeting.TestGreeting.test_default_name`, for every `test_*` method of every
class in an addon's `tests/` package (custom_addons/, addons/, odoo/addons/).

What it counts is what is WRITTEN, not what Odoo would run: a test skipped by tag or by a
`skipTest` still counts, and inheritance is not followed. That is the right measure for the gate
this feeds (a change that deletes or empties tests), and it never prints anything but ids.
"""

from __future__ import annotations

import ast
import sys
from pathlib import Path

ROOTS = ("custom_addons", "addons", "odoo/addons")


def tests_of(addon: Path):
    tests = addon / "tests"
    if not tests.is_dir():
        return
    for py in sorted(tests.rglob("*.py")):
        try:
            tree = ast.parse(py.read_bytes())
        except (SyntaxError, ValueError):
            continue
        dotted = ".".join(py.relative_to(addon).with_suffix("").parts)
        for node in tree.body:
            if isinstance(node, ast.ClassDef):
                for item in node.body:
                    if isinstance(item, (ast.FunctionDef, ast.AsyncFunctionDef)) \
                            and item.name.startswith("test"):
                        yield f"{addon.name}.{dotted}.{node.name}.{item.name}"


def main(checkout: str) -> None:
    base = Path(checkout)
    ids: set[str] = set()
    for root in ROOTS:
        for manifest in sorted((base / root).glob("*/__manifest__.py")):
            ids.update(tests_of(manifest.parent))
    sys.stdout.write("".join(f"{i}\n" for i in sorted(ids)))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
