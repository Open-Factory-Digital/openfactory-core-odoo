# Attaching an existing Odoo Community fork

`install.sh` gives you a fresh fork. If you already have one — your own series branch, your own
`custom_addons/`, years of history — put the factory on it instead:

```bash
./install.sh --dir ~/openfactory-odoo        # once: the factory and its tools (also clones a
                                             # fresh 20.0 fork as project 'odoo'; ignore it or
                                             # `of-odoo of project remove odoo`)
of-odoo attach ~/src/acme-odoo --name acme --base 17.0
of-odoo prove -p acme
of-odoo up -p acme                           # Odoo 17 on the next free port (8070, …)
```

`attach` accepts:

| source | what happens |
|---|---|
| a **local checkout** | registered in place with `forge: local`: the checkout is the forge. The factory works in worktrees of it and fast-forwards the base branch when you merge. Your working tree is only touched by that fast-forward, and only when it is safe (core refuses, by name, if you have edits over the same lines). |
| a **GitHub URL** (`https://github.com/acme/odoo.git`) | shallow-cloned at `--base` into `<dir>/forks/<name>` and registered with `forge: github` (`acme/odoo`): pull requests are opened on GitHub. Needs a token, see [github-forge.md](github-forge.md). |
| any other **clone URL** | shallow-cloned the same way and registered with `forge: local` — the clone is the forge; push its base branch back to your remote yourself. |

The Odoo series is read from `odoo/release.py`, so the dev image (`FROM odoo:<series>`) and the
manifest's version convention match the fork. `--base` defaults to the checkout's current branch.

**One thing is written beside your checkout:** core's worktree box keeps each job's worktree in
`<parent of the checkout>/.openfactory-worktrees/` (`factory.py`; still not configurable in
v0.6.0) — for `~/src/acme-odoo` that is `~/src/.openfactory-worktrees/` — and removes it when the
job ends. Job journals go inside the install (`OPENFACTORY_LOG_DIR`, set by
`of-odoo`).

## Nothing has to be committed to your fork

By default the project's manifest is **operator-held**: `of-odoo` writes it to
`<dir>/manifests/<name>.yaml` and registers its absolute path as the project's `manifest_path`.
Core joins `repo_root / manifest_path` (`namespace.resolve`) and an absolute right-hand side wins,
so the gate, the proof and every job read that file — and your fork's history stays yours. The
Odoo guidelines are the deployment's (`<dir>/guidelines/`), also outside the fork.

Edit `<dir>/manifests/<name>.yaml` to change a gate, then `of-odoo prove -p <name>` again (the
proof notices changed commands by their hash). Re-running `attach` or `register` rewrites it from
the template.

## …or commit it

`--committed` writes `.openfactory/project.yaml` into the checkout instead and registers the
default `manifest_path`. Its commands call `of-odoo validate … -p <name>` (on the factory's
`PATH`), so nothing in it is specific to one machine. Commit it **on the base branch** — with
`-f`, because Odoo's own `.gitignore` ignores every dot-directory (`.*`):

```bash
of-odoo attach ~/src/acme-odoo --name acme --committed
git -C ~/src/acme-odoo add -f .openfactory/project.yaml
git -C ~/src/acme-odoo commit -m "Add OpenFactory manifest"
```

The committed route makes the manifest reviewable like code, and changes to it go through pull
requests — the platform's floor protects `.openfactory/**`, so the agent can propose a change to
it but never merge one unattended.

## Where your addons live

Validation maps a changed file to the nearest directory holding a `__manifest__.py`, so addons in
`custom_addons/`, `addons/` or `odoo/addons/` are tested as they are. The dev server's addons path
is `custom_addons/`, `addons/`, `odoo/addons/`; for other directories add
`OF_ODOO_EXTRA_ADDONS='my_addons oca/web'` (relative to the checkout root) to
`<dir>/projects/<name>.env` — the dev server and validation both read it. Copy-mode validation
overlays changed modules of the three standard roots only; a module elsewhere falls back to a full
copy of the tree, which is slower but correct.
