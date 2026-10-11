# The GitHub forge

```bash
./install.sh --forge github --github-owner <your-user-or-org>
```

1. `gh repo fork odoo/odoo` to that owner (`--org` when it is not your own user), unless
   `<owner>/odoo` already exists. GitHub forks every branch server-side; nothing is downloaded.
2. A shallow single-branch clone of `<owner>/odoo` at `--odoo-version` into `<dir>/odoo`, with
   `upstream` pointing at odoo/odoo.
3. `openfactory init --forge github --github-auth token` for the isolated deployment, and the token
   of your `gh` login written to `OPENFACTORY_BOT_TOKEN` in `<dir>/home/.openfactory/env` (mode
   0600). Commits and pull requests read as you. For a separate identity use a GitHub App instead
   (core: `docs/setup/github.md`).
4. The project is registered with `forge: github` (`<owner>/odoo`), `tracker: local` (cards on the
   panel's Board — no GitHub Projects board is created) and `ci: none` (the manifest's `validate:`
   is the gate; odoo/odoo's own CI is not run on a fork).

The job box is still the local worktree box: work happens in a worktree of `<dir>/odoo`, and the
branch is pushed to your fork. A push from a shallow clone works because the fork already has the
base commit. Merge the pull request on GitHub; the factory polls it and moves the card to Done.
After merging, `git -C <dir>/odoo pull --ff-only` (or `fetch` + `restart` in copy mode) and
`of-odoo update <module>` to see it locally.

`install.sh --forge github --github-owner X --dry-run` prints the fork, clone and register steps
without running them; this sample's CI runs exactly that.

## An existing fork on GitHub

`of-odoo attach https://github.com/acme/odoo.git --base 17.0` — see [attach.md](attach.md).
