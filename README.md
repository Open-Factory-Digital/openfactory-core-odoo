# openfactory-core-odoo

A sample implementation of [OpenFactory](https://github.com/Open-Factory-Digital/openfactory-core)
with **Odoo Community** as the product. One script installs the factory, forks Odoo onto a forge
and leaves both ready: you run your Odoo instance, write a card on the factory floor ("add a module
that…"), the factory's coding agent writes it in your fork, Odoo's own tests prove it, and you
merge it and see it in Odoo.

It is also the shortest way to put the factory on an Odoo fork **you already have**
(`of-odoo attach`, below).

```
 install.sh ──► <dir>/core        openfactory-core, cloned at a release tag, in its own venv
            ──► <dir>/odoo        your Odoo fork: the forge the factory branches from and merges to
            ──► <dir>/home        the factory's own HOME — registry, board, proofs (isolated)
            ──► <dir>/manifests   the operator-held project manifests (nothing committed to Odoo)
            ──► <dir>/guidelines  the Odoo house rules every agent pass reads
            ──► <dir>/bin/of-odoo the one command for all of it
```

## Quickstart

You need: `git`, Python ≥ 3.12, Docker (with compose), the [`temporal`
CLI](https://docs.temporal.io/cli) on `PATH`, and a coding agent signed in — `claude` by default
(`claude` once, interactively, is enough). No sudo, no account anywhere for the local forge.

```bash
git clone https://github.com/Open-Factory-Digital/openfactory-core-odoo.git
cd openfactory-core-odoo
./install.sh                         # → ~/openfactory-odoo, Odoo 19.0, local forge
export PATH="$HOME/openfactory-odoo/bin:$PATH"

of-odoo doctor                       # the factory's own checklist for project 'odoo'
of-odoo prove                        # runs setup + validate once, asks the agent one question
of-odoo up                           # Odoo at http://localhost:8069 — admin / admin
of-odoo factory up                   # engine, worker, panel → http://127.0.0.1:18787
```

`./install.sh --help` lists the options: `--dir`, `--odoo-version 16.0…20.0` (default 19.0),
`--core-version` (default `v0.5.0`), `--forge local|github`, `--github-owner`, the four ports and
`--dry-run`, which prints every step and writes nothing. Re-running it converges: nothing that
exists is cloned or overwritten again except this sample's own scripts.

**Measured** (this machine, 2026-10-11, Odoo 19.0, core v0.5.0): the whole install took 74 s.
The shallow single-branch clone of `odoo/odoo@19.0` took 27 s — 48,259 files, 1.4 GB on disk of
which 225 MB is `.git`; the full history would be several GB. The `odoo:19.0` base image the dev
image builds on is 3.2 GB. `of-odoo up` on a fresh database (Odoo's `base` installed, no demo
data) answered `/web/login` 200 after 31 s.

### Write a card, get a pull request, see it in Odoo

1. Open the panel (`http://127.0.0.1:18787`) › project **odoo** › **Board** › **new card**, and
   paste [examples/cards/01-x-hello.md](examples/cards/01-x-hello.md) — or from a shell:

   ```bash
   of-odoo of act card_create -p odoo -P title="Add a custom module x_hello" \
       -P body="$(sed -n '/^## Objective/,$p' examples/cards/01-x-hello.md)"
   of-odoo of act card_move -p odoo -i 1 -P column=TO-DO
   ```

2. A card in **TO-DO** is picked up: the agent works in a git worktree of your fork (never your
   checkout), the gates below run, an independent review comments, and a **pull request** opens on
   the local forge (the panel shows it). The card moves to **In review**.
3. Read the diff in the panel and merge it there (or `of-odoo of act merge -p odoo -i 1`). On the
   local forge a merge fast-forwards `19.0` in `<dir>/odoo`. The card goes to **Done**.
4. See it in Odoo:

   ```bash
   of-odoo restart                   # copy mode: re-syncs the source first (see below)
   of-odoo install x_hello           # installs the module into the dev database
   ```

   Hello › Greetings is in the menu. After later changes to a module: `of-odoo update x_hello`.

## How it fits together

### The factory, isolated from any other

openfactory-core keeps all operator state under `$HOME/.openfactory/` (`namespace.operator_path`)
and always loads `~/.openfactory/env` (`cli.py`, `_HOST_ENV`); there is no `OPENFACTORY_HOME`.
So `of-odoo` runs every `openfactory` process with `HOME=<dir>/home`, and hands back only what the
tools need from your real home: the agent's login (`<dir>/home/.claude` is a symlink to
`~/.claude`), your git identity (copied into `<dir>/home/.gitconfig`), `DOCKER_CONFIG` and
`GH_CONFIG_DIR`. The engine, its UI and the panel listen on **17233 / 18233 / 18787**, not the
platform's 7233 / 8233 / 8787, so this sample runs beside a factory you already have without
reading or writing anything of it. `of-odoo env` prints the environment, `of-odoo of <args>` runs
any `openfactory` command inside it.

### The fork on a forge

- **`--forge local`** (default): `odoo/odoo` is cloned shallow (`--depth 1 --single-branch`) into
  `<dir>/odoo`, and that checkout **is** the forge — core's `forge: local` branches from it, keeps
  its pull requests beside the registry and fast-forwards the base branch on merge. `upstream`
  points at odoo/odoo for updates. A shallow repository is a working forge: worktrees, and the
  clones core makes from it (`clone --depth 1 <path>`, `clone --local --no-hardlinks`,
  `file://` clones) were each checked against it (14–16 s apiece; git notes the source is shallow
  and proceeds).
- **`--forge github --github-owner <you|org>`**: `gh repo fork odoo/odoo` to that owner, a shallow
  clone of the fork, and core's `forge: github` — branches pushed and pull requests opened on
  github.com, with the `gh` login's token. See [docs/github-forge.md](docs/github-forge.md).

openfactory-core itself is **cloned, not forked**: you run a released platform, pinned to a tag.
Fork it only if you are going to patch the platform; then point `OF_CORE_REPO` at your fork.

### What the agent is held to

The manifest ([templates/project.yaml.tmpl](templates/project.yaml.tmpl)) is operator-held — an
absolute `manifest_path` in the registry, which core's `namespace.resolve` honours for every
reader — so nothing is committed to the fork. It declares:

| | |
|---|---|
| `base_branch` | the Odoo series branch (`19.0`) |
| `setup` | Docker answers, the dev image exists, Postgres is up |
| `validate.test` | **Odoo tests of only the addons this change touches**: the diff against the merge-base (committed or not, untracked included) is mapped to addon directories (the nearest `__manifest__.py`, so `custom_addons/`, `addons/`, `odoo/addons/` all work); those modules are installed into a throwaway database with `--test-enable --test-tags /<module>,… --stop-after-init`, in the dev image, against the project's Postgres, and the database is dropped. Code outside any addon also runs `base` (override: `OF_ODOO_FRAMEWORK_TESTS`). Fails on a non-zero exit, a failing test, or any `ERROR`/`CRITICAL` log line. |
| `validate.lint` | changed files only: Python compiles, XML parses, CSV reads, `__manifest__.py` is a literal dict with a `name`, `ir.model.access.csv` has its header; warnings for a version not `19.0.x.y.z`, a missing `license`, a new model without access rules |
| `validate.security` | a credential added by the change (changed files only). It replaces the platform floor's whole-tree scan, which reports Odoo's own test keys on every run. |
| `test_inventory` | every `test_*` method of every addon's `tests/`, read statically (15,690 ids on 19.0, 2.5 s), one id per line — so a change that deletes tests is gated |
| `merge_policy` / `review_mode` | `human` / `advisory` |
| `knowledge_map` / `okf_gate` | off — a module map of ~600 addons buys little while work lives in a few custom modules; turn on when you want it |
| `max_cost_usd`, `max_diff_lines` | 5.0 (per-token billing only) and 1500 |
| `components` | `custom_addons/**`, `addons/**` normal; `odoo/**` (the framework) high-risk. `stack: odoo` names no preset on purpose: the `python` preset would add `mypy .` and `bandit -r .` over all of Odoo. |

The agent's Odoo conventions — new modules in `custom_addons/`, never patch core modules unless the
card says so, `19.0.x.y.z` versions, `ir.model.access.csv` for every model, a `tests/` package —
are in [templates/guidelines/odoo.md](templates/guidelines/odoo.md), installed as
`<dir>/guidelines/` and served to every pass as the deployment's own guidelines
(`OPENFACTORY_GUIDELINES_DIR`). Edit them there.

### Odoo in Docker, from your checkout

[docker/Dockerfile](docker/Dockerfile) is `FROM odoo:<series>` — Odoo's own runtime, Python
dependencies and wkhtmltopdf — but runs `odoo-bin` **from your fork** at `/opt/odoo/src`, with an
addons path computed from `custom_addons/`, `addons/`, `odoo/addons/`. The host needs no Odoo
Python dependencies, and validation uses the same image, so the gate and the dev server run the
same code the same way. Postgres 16 is never published; Odoo is on `127.0.0.1:8069`. Memory caps:
Odoo 2 GB, Postgres 1 GB.

The checkout reaches the container one of two ways, chosen by probing at register time:

- **mount** — bind-mounted; an edit is live after `of-odoo restart`.
- **copy** — when the Docker daemon cannot see the path (snap-confined Docker and anything under
  `/tmp`, a remote daemon): the committed tree is synced into a volume (`git archive`, ~10 s for
  19.0) and validation streams just the changed addons over it. Uncommitted edits are not visible
  to `of-odoo up` in this mode; commit, then `of-odoo restart`.

The factory's job box on this door is core's `worktree` box (no container): `setup`/`validate`
run on the host in a worktree of the fork, and it is the scripts that reach into Docker. `setup`
starts the project's Postgres and leaves it running for the next job; `of-odoo down` stops it.

## Commands

| | |
|---|---|
| `of-odoo up \| down \| restart \| logs \| ps \| build [-p P]` | the Odoo dev server of project P (default: `odoo`) |
| `of-odoo install \| update MODULE [-p P]` | install / upgrade modules in the dev database, then restart |
| `of-odoo odoo [-p P] ARGS…` | any `odoo-bin` invocation against the dev database |
| `of-odoo factory up \| fg \| down \| status \| logs` | the factory (engine, worker, panel), in the background or foreground |
| `of-odoo doctor \| prove [-p P]` | `openfactory doctor` / `openfactory box prove` |
| `of-odoo validate test\|lint\|security\|setup\|inventory [-p P]` | a gate by hand, from a checkout or worktree of the fork |
| `of-odoo attach PATH\|URL [--name N] [--base B] [--committed]` | put an existing fork on the floor — [docs/attach.md](docs/attach.md) |
| `of-odoo projects`, `of-odoo env`, `of-odoo of ARGS…` | what is registered, the isolated environment, any `openfactory` command |

## What this does not do (yet)

- **Previews** (core's `preview:` block, ADR-0050) are not wired. A preview builds the services a
  change touched from the change's own Dockerfiles, from a compose file committed on the base
  branch; this dev stack instead runs Odoo from a mounted or synced checkout and lives outside the
  fork. Wiring it means committing a compose file whose Odoo image `COPY`s the tree — possible,
  but a 1.4 GB build context per preview. Until then: merge, `of-odoo restart`, look.
- **Odoo Enterprise** is out of scope: it is not open source and is not fetched.
- The dev database is for development. Nothing here is a production deployment of Odoo.

## Licence

This sample is Apache-2.0 ([LICENSE](LICENSE)). Odoo Community is LGPL-3 and is **not vendored**
here: `install.sh` clones it from github.com/odoo/odoo onto your machine, under its own licence.
openfactory-core is cloned likewise, under its own licence.
