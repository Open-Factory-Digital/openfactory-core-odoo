# Troubleshooting

**`of-odoo doctor` says `processes` FAIL.** The factory is not running: `of-odoo factory up`
(`of-odoo factory logs` if it does not come up). Port taken? Re-run `install.sh` with
`--engine-port/--engine-ui-port/--panel-port`, then `of-odoo factory down && of-odoo factory up`.

**`box_proof` FAIL / cards stay in TO-DO ("held").** `of-odoo prove`. A changed gate command needs
a new proof.

**`harness answer` FAIL in the proof.** The agent cannot sign in from the isolated home. Check
`<dir>/home/.claude` is a symlink to your `~/.claude`, and that `claude -p hi` works for you.
Alternatively export `CLAUDE_CODE_OAUTH_TOKEN` (from `claude setup-token`) before
`of-odoo factory up`.

**The Docker daemon "cannot see" the checkout (copy mode).** A remote daemon sees none of your
files; if your Docker is the snap package, it cannot read `/tmp` or hidden directories. Copy mode
handles it (`of-odoo projects` shows the mode). To use mount mode instead, keep the install and
your forks under your home directory, outside a dot-directory — that works with snap Docker too.

**A docker command exits 1 and prints nothing.** If your Docker is the snap package, its CLI
cannot write to a regular file it inherits as stdout/stderr (`write /dev/stdout: bad file
descriptor`, often swallowed with the rest of the output) — measured with files under `$HOME` as
well as `/tmp` — nor read a redirected stdin from `/tmp`. `of-odoo` pipes everything (that is why
the compose file and build context go over a pipe), and the factory reads its gates over pipes;
if you redirect `of-odoo validate` or `of-odoo up` yourself, go through `| cat` (`… 2>&1 | cat >
log`), not straight to a file.

**A module does not load on 20.0: `KeyError: 'ir.model.access'`.** Odoo 20.0 replaced
`ir.model.access` and `ir.rule` with `ir.access`: the module ships `security/ir.model.access.csv`
from an older series. Rewrite it as `security/ir.access.csv`
(`id,name,model_id,group_id/id,operation,domain`, `model_id` the model's technical name,
`operation` e.g. `crud` or `r`) and list that file in the manifest. `of-odoo validate lint`
reports the old file on 20.0.

**`validate` runs `base` tests and takes long.** The change touched code outside any addon (the
framework, `odoo-bin`, …). That is what the guidelines tell the agent not to do; if it is intended,
set `OF_ODOO_FRAMEWORK_TESTS` to a narrower module list in the factory's environment.

**`of-odoo up` times out.** `of-odoo logs`. A first start creates the database (`base`, about a
minute). A stale database from another series: `of-odoo down`, then
`docker volume rm <compose project>_pgdata` (`of-odoo ps` names the project).

**Updating Odoo from upstream.** The fork is shallow. `git -C <dir>/odoo fetch --depth 500 upstream
20.0 && git -C <dir>/odoo merge upstream/20.0` (your series); if git reports unrelated histories, deepen more
(`--deepen 2000`) or once `--unshallow` (several GB). Then `of-odoo restart` and update modules.

**Starting over.** `of-odoo factory down`, `of-odoo down` (per project), then delete `<dir>` and
the Docker volumes named `ofodoo-*`. Nothing outside `<dir>` was written, except Docker's volumes
and images (`of-odoo-dev:<series>`, `odoo:<series>`, `postgres:16-alpine`).
