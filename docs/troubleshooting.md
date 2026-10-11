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

**The Docker daemon "cannot see" the checkout (copy mode).** Snap-installed Docker cannot read
`/tmp` or hidden directories, and a remote daemon sees none of your files. Copy mode handles it
(`of-odoo projects` shows the mode). To use mount mode instead, install under your home directory,
outside a dot-directory, with a non-snap Docker.

**A docker command exits 1 and prints nothing.** Snap-confined Docker also cannot write to a file
under `/tmp` it inherits as stdout/stderr, nor read a redirected stdin from there. `of-odoo` pipes
everything (that is why the compose file and build context go over a pipe); if you redirect its
output yourself, redirect to a file outside `/tmp` or through `| cat`.

**`validate` runs `base` tests and takes long.** The change touched code outside any addon (the
framework, `odoo-bin`, …). That is what the guidelines tell the agent not to do; if it is intended,
set `OF_ODOO_FRAMEWORK_TESTS` to a narrower module list in the factory's environment.

**`of-odoo up` times out.** `of-odoo logs`. A first start creates the database (`base`, about a
minute). A stale database from another series: `of-odoo down`, then
`docker volume rm <compose project>_pgdata` (`of-odoo ps` names the project).

**Updating Odoo from upstream.** The fork is shallow. `git -C <dir>/odoo fetch --depth 500 upstream
19.0 && git -C <dir>/odoo merge upstream/19.0`; if git reports unrelated histories, deepen more
(`--deepen 2000`) or once `--unshallow` (several GB). Then `of-odoo restart` and update modules.

**Starting over.** `of-odoo factory down`, `of-odoo down` (per project), then delete `<dir>` and
the Docker volumes named `ofodoo-*`. Nothing outside `<dir>` was written, except Docker's volumes
and images (`of-odoo-dev:<series>`, `odoo:<series>`, `postgres:16-alpine`).
