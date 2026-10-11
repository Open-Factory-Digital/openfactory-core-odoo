"""Register (or re-register) one Odoo fork with this install's isolated factory.

    python register.py NAME REPO_PATH FORGE_KIND FORGE_REPO MANIFEST_PATH

Runs with the install's HOME, so `ProjectRegistry()` is `<install>/home/.openfactory/registry.yaml`.

The tracker is always `local` (cards on the panel's Board, a file in the isolated home) and CI is
`none`: the manifest's `validate:` is the gate. The forge is `local` (the checkout IS the forge:
the factory branches, opens the pull request and fast-forwards the base right there) or `github`
(pull requests on github.com/FORGE_REPO; needs OPENFACTORY_BOT_TOKEN in the deployment env).

MANIFEST_PATH absolute = operator-held: `namespace.resolve(repo_root, manifest_path)` joins
`repo_root / manifest_path`, and an absolute right-hand side wins, so every reader of the manifest
reads this file and nothing has to be committed to the fork. Empty = the committed default,
`.openfactory/project.yaml` on the base branch.
"""

from __future__ import annotations

import sys

from openfactory.contracts.project import ProductConfig, Project, ProviderRef
from openfactory.registry import ProjectRegistry


def main(name: str, repo_path: str, forge: str, forge_repo: str, manifest: str) -> None:
    reg = ProjectRegistry()
    fields: dict = {
        "name": name,
        "repo_path": repo_path,
        "forge": ProviderRef(kind=forge, repo=forge_repo if forge == "github" else name, options={}),
        "tracker": ProviderRef(kind="local", repo=name, options={}),
        "ci": ProviderRef(kind="none", repo=name, options={}),
        "product": ProductConfig(docs_repo=f"{name}-context"),
    }
    if manifest:
        fields["manifest_path"] = manifest
    try:
        existing = reg.get(name)
    except KeyError:
        existing = None
    if existing is not None:
        merged = existing.model_dump(mode="json")
        merged.update(Project(**fields).model_dump(mode="json", include=set(fields) | {"manifest_path"}))
        if not manifest:
            merged["manifest_path"] = Project(name=name, repo_path=repo_path).manifest_path
        reg.remove(name)
        reg.add(Project(**merged))
        print(f"re-registered {name} in {reg.path}")
    else:
        reg.add(Project(**fields))
        print(f"registered {name} in {reg.path}")


if __name__ == "__main__":
    if len(sys.argv) != 6:
        sys.exit(__doc__)
    main(*sys.argv[1:])
