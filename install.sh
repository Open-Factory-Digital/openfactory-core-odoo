#!/bin/sh
# install.sh — OpenFactory + an Odoo Community fork, ready to customise from the factory floor.
#
#   ./install.sh [--dir DIR] [--odoo-version 19.0] [--core-version v0.5.0]
#                [--forge local|github] [--github-owner OWNER] [--project NAME]
#                [--odoo-port 8069] [--panel-port 18787] [--engine-port 17233]
#                [--engine-ui-port 18233] [--no-docker] [--dry-run]
#
# Idempotent: re-running converges (nothing that exists is re-cloned or overwritten, except this
# sample's own scripts, which are refreshed). No sudo. Nothing outside DIR is written, except the
# GitHub fork when --forge github is asked for.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)

DIR="${HOME}/openfactory-odoo"
ODOO_VERSION=19.0
CORE_VERSION=v0.5.0
CORE_REPO=${OF_CORE_REPO:-https://github.com/Open-Factory-Digital/openfactory-core.git}
ODOO_UPSTREAM=${OF_ODOO_UPSTREAM:-https://github.com/odoo/odoo.git}
FORGE=local
GITHUB_OWNER=""
PROJECT=odoo
ODOO_PORT=""
PANEL_PORT=""
ENGINE_PORT=""
ENGINE_UI_PORT=""
DOCKER=yes
DRY=no

usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
    case $1 in
        --dir) DIR=$2; shift 2 ;;
        --odoo-version) ODOO_VERSION=$2; shift 2 ;;
        --core-version) CORE_VERSION=$2; shift 2 ;;
        --forge) FORGE=$2; shift 2 ;;
        --github-owner) GITHUB_OWNER=$2; shift 2 ;;
        --project) PROJECT=$2; shift 2 ;;
        --odoo-port) ODOO_PORT=$2; shift 2 ;;
        --panel-port) PANEL_PORT=$2; shift 2 ;;
        --engine-port) ENGINE_PORT=$2; shift 2 ;;
        --engine-ui-port) ENGINE_UI_PORT=$2; shift 2 ;;
        --no-docker) DOCKER=no; shift ;;
        --dry-run) DRY=yes; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "install.sh: unknown option $1" >&2; usage >&2; exit 2 ;;
    esac
done

case $FORGE in
    local) ;;
    github) [ -n "$GITHUB_OWNER" ] || { echo "install.sh: --forge github needs --github-owner <user|org>" >&2; exit 2; } ;;
    *) echo "install.sh: --forge must be local or github" >&2; exit 2 ;;
esac
case $ODOO_VERSION in
    1[6-9].0|20.0) ;;
    *) echo "install.sh: --odoo-version $ODOO_VERSION is not one this sample knows (16.0–20.0)" >&2; exit 2 ;;
esac
case $DIR in /*) ;; *) DIR="$(pwd)/$DIR" ;; esac

step() { printf '\n==> %s\n' "$*"; }
run() {
    if [ "$DRY" = yes ]; then printf '  [dry-run] %s\n' "$*"; else "$@"; fi
}
have() { command -v "$1" >/dev/null 2>&1; }

# ── 0. what this machine has ─────────────────────────────────────────────────────────────────
step "checking prerequisites"
missing=""
have git || missing="$missing git"
PY=""
for c in python3.14 python3.13 python3.12 python3; do
    if have "$c" && "$c" -c 'import sys; sys.exit(sys.version_info < (3, 12))' 2>/dev/null; then PY=$c; break; fi
done
[ -n "$PY" ] || missing="$missing python>=3.12"
[ "$FORGE" = github ] && ! have gh && missing="$missing gh"
if [ -n "$missing" ]; then
    if [ "$DRY" = yes ]; then echo "  (dry-run) would stop here — missing:$missing"
    else echo "install.sh: missing:$missing" >&2; exit 1; fi
fi
have claude || echo "  ! no 'claude' on PATH — the factory's coding agent; install and sign in (see README)"
have temporal || echo "  ! no 'temporal' on PATH — 'of-odoo factory' needs it (https://docs.temporal.io/cli)"
if [ "$DOCKER" = yes ] && ! have docker; then
    echo "  ! no 'docker' on PATH — the Odoo dev server and validation run in Docker; continuing with --no-docker"
    DOCKER=no
fi
echo "  install dir: $DIR"
echo "  odoo $ODOO_VERSION · openfactory-core $CORE_VERSION · forge $FORGE${GITHUB_OWNER:+ ($GITHUB_OWNER)}"

# Keep earlier answers on a re-run (ports are the ones a person edits).
if [ -f "$DIR/of-odoo.env" ]; then
    # shellcheck disable=SC1091
    . "$DIR/of-odoo.env"
fi
ODOO_PORT=${ODOO_PORT:-${OF_ODOO_HTTP_PORT_DEFAULT:-8069}}
PANEL_PORT=${PANEL_PORT:-${OF_PANEL_PORT:-18787}}
ENGINE_PORT=${ENGINE_PORT:-${OF_TEMPORAL_PORT:-17233}}
ENGINE_UI_PORT=${ENGINE_UI_PORT:-${OF_TEMPORAL_UI_PORT:-18233}}
REAL_HOME=${OF_ODOO_REAL_HOME:-$HOME}

run mkdir -p "$DIR"

# ── 1. openfactory-core, cloned at a release, in its own venv ───────────────────────────────
step "openfactory-core $CORE_VERSION"
if [ -d "$DIR/core/.git" ]; then
    have_ver=$(git -C "$DIR/core" describe --tags --exact-match 2>/dev/null || echo "?")
    if [ "$have_ver" != "$CORE_VERSION" ]; then
        run git -C "$DIR/core" fetch --depth 1 origin "refs/tags/$CORE_VERSION:refs/tags/$CORE_VERSION"
        run git -C "$DIR/core" -c advice.detachedHead=false checkout -q "$CORE_VERSION"
    else
        echo "  already at $CORE_VERSION"
    fi
else
    run git -c advice.detachedHead=false clone -q --depth 1 --branch "$CORE_VERSION" "$CORE_REPO" "$DIR/core"
fi
if [ "$DRY" = no ] && [ -x "$DIR/core/.venv/bin/openfactory" ] \
   && [ "$(cat "$DIR/core/.venv/.of-odoo-core" 2>/dev/null)" = "$CORE_VERSION" ]; then
    echo "  venv ready"
else
    run "$PY" -m venv "$DIR/core/.venv"
    run "$DIR/core/.venv/bin/pip" install -q --upgrade pip
    run "$DIR/core/.venv/bin/pip" install -q -e "$DIR/core[runtime]"
    [ "$DRY" = yes ] || echo "$CORE_VERSION" > "$DIR/core/.venv/.of-odoo-core"
fi

# ── 2. this sample's scripts, docker files and guidelines ───────────────────────────────────
step "of-odoo scripts"
run mkdir -p "$DIR/bin" "$DIR/lib" "$DIR/docker" "$DIR/templates" "$DIR/projects" "$DIR/manifests"
for f in bin/of-odoo lib/common.sh lib/odoo-validate.sh lib/odoo_lint.py lib/odoo_test_inventory.py \
         lib/register.py docker/Dockerfile docker/compose.yaml docker/of-odoo-run docker/of-odoo-test \
         templates/project.yaml.tmpl; do
    run cp "$HERE/$f" "$DIR/$f"
done
run chmod +x "$DIR/bin/of-odoo" "$DIR/lib/odoo-validate.sh" "$DIR/docker/of-odoo-run" "$DIR/docker/of-odoo-test"
if [ ! -d "$DIR/guidelines" ]; then
    run cp -R "$HERE/templates/guidelines" "$DIR/guidelines"
else
    echo "  guidelines/ kept (yours to edit)"
fi

# ── 3. the isolated home: this install's factory never reads or writes ~/.openfactory ────────
step "isolated factory home ($DIR/home)"
run mkdir -p "$DIR/home"
if [ -d "$REAL_HOME/.claude" ] && [ ! -e "$DIR/home/.claude" ]; then
    # The coding agent's login is the one credential the local door needs: share it.
    run ln -s "$REAL_HOME/.claude" "$DIR/home/.claude"
fi
if [ ! -f "$DIR/home/.claude.json" ]; then
    if [ "$DRY" = yes ]; then echo "  [dry-run] seed $DIR/home/.claude.json"
    else echo '{"hasCompletedOnboarding": true}' > "$DIR/home/.claude.json"; fi
fi
if [ ! -f "$DIR/home/.gitconfig" ]; then
    gname=$(git config --global user.name 2>/dev/null || echo "OpenFactory Odoo")
    gmail=$(git config --global user.email 2>/dev/null || echo "openfactory@localhost")
    run git config --file "$DIR/home/.gitconfig" user.name "$gname"
    run git config --file "$DIR/home/.gitconfig" user.email "$gmail"
fi

if [ "$DRY" = no ]; then
    cat > "$DIR/of-odoo.env" <<EOF
# of-odoo install config — written by install.sh, safe to edit (then: of-odoo factory restart)
OF_ODOO_DIR='$DIR'
OF_ODOO_REAL_HOME='$REAL_HOME'
OF_ODOO_DEFAULT_PROJECT='${OF_ODOO_DEFAULT_PROJECT:-$PROJECT}'
OF_ODOO_HTTP_PORT_DEFAULT=$ODOO_PORT
OF_TEMPORAL_PORT=$ENGINE_PORT
OF_TEMPORAL_UI_PORT=$ENGINE_UI_PORT
OF_PANEL_PORT=$PANEL_PORT
EOF
else
    echo "  [dry-run] write $DIR/of-odoo.env (engine :$ENGINE_PORT, engine UI :$ENGINE_UI_PORT, panel :$PANEL_PORT)"
fi

ENVFILE="$DIR/home/.openfactory/env"
if [ -f "$ENVFILE" ]; then
    echo "  deployment env exists — kept"
else
    if [ "$FORGE" = github ]; then
        init_axes="--forge github --github-auth token"
    else
        init_axes="--forge local"
    fi
    # shellcheck disable=SC2086
    run env HOME="$DIR/home" "$DIR/core/.venv/bin/openfactory" init --runtime local $init_axes \
        --tracker local --harness claude_code --claude-auth subscription --channel panel --panel-local
    if [ "$FORGE" = github ]; then
        # forge github signs in with a token: the gh login's, so commits and PRs read as you
        if [ "$DRY" = yes ]; then
            echo "  [dry-run] OPENFACTORY_BOT_TOKEN=\$(gh auth token) into $ENVFILE"
        elif tok=$(gh auth token 2>/dev/null) && [ -n "$tok" ]; then
            grep -v '^OPENFACTORY_BOT_TOKEN=' "$ENVFILE" > "$ENVFILE.new" || true
            printf 'OPENFACTORY_BOT_TOKEN=%s\n' "$tok" >> "$ENVFILE.new"
            chmod 600 "$ENVFILE.new" && mv "$ENVFILE.new" "$ENVFILE"
        else
            echo "  ! no gh login — put a token with repo scope in OPENFACTORY_BOT_TOKEN in $ENVFILE"
        fi
    fi
    if [ "$DRY" = no ]; then
        # The three listeners on THIS install's ports (of-odoo also exports them, which wins).
        sed -i.bak \
            -e "s|^TEMPORAL_ADDRESS=.*|TEMPORAL_ADDRESS=127.0.0.1:$ENGINE_PORT|" \
            -e "s|^TEMPORAL_UI_URL=.*|TEMPORAL_UI_URL=http://127.0.0.1:$ENGINE_UI_PORT|" \
            -e "s|^OPENFACTORY_PANEL_URL=.*|OPENFACTORY_PANEL_URL=http://127.0.0.1:$PANEL_PORT|" \
            "$ENVFILE" && rm -f "$ENVFILE.bak"
    fi
fi

# ── 4. the Odoo fork ─────────────────────────────────────────────────────────────────────────
SRC="$DIR/odoo"
step "Odoo Community $ODOO_VERSION fork ($FORGE) → $SRC"
if [ "$FORGE" = github ]; then
    if [ "$DRY" = yes ] || ! gh repo view "$GITHUB_OWNER/odoo" >/dev/null 2>&1; then
        if [ "$(gh api user --jq .login 2>/dev/null || true)" = "$GITHUB_OWNER" ]; then
            run gh repo fork odoo/odoo --clone=false
        else
            run gh repo fork odoo/odoo --clone=false --org "$GITHUB_OWNER"
        fi
    else
        echo "  $GITHUB_OWNER/odoo already exists"
    fi
    CLONE_FROM="https://github.com/$GITHUB_OWNER/odoo.git"
else
    CLONE_FROM="$ODOO_UPSTREAM"
fi
if [ -d "$SRC/.git" ]; then
    echo "  checkout exists — kept ($(git -C "$SRC" rev-parse --abbrev-ref HEAD))"
else
    t0=$(date +%s)
    # Shallow and single-branch: the whole history is ~4 GB; one branch at depth 1 is enough to
    # branch from, and the local forge clones/worktrees from it (README: measured).
    run git -c advice.detachedHead=false clone --depth 1 --single-branch --branch "$ODOO_VERSION" "$CLONE_FROM" "$SRC"
    if [ "$DRY" = no ]; then
        t1=$(date +%s)
        echo "  cloned in $((t1 - t0))s, $(du -sh "$SRC" | cut -f1) on disk"
        if [ "$FORGE" = local ]; then
            # The checkout IS the forge now; upstream stays reachable for updates.
            git -C "$SRC" remote rename origin upstream
        else
            git -C "$SRC" remote add upstream "$ODOO_UPSTREAM"
        fi
    fi
fi

# ── 5. the dev image ────────────────────────────────────────────────────────────────────────
IMAGE="of-odoo-dev:$ODOO_VERSION"
SRC_MODE=mount
if [ "$DOCKER" = yes ]; then
    step "Odoo dev image $IMAGE (FROM odoo:$ODOO_VERSION)"
    if [ "$DRY" = yes ]; then
        echo "  [dry-run] tar -C $DIR/docker -cf - . | docker build --build-arg ODOO_VERSION=$ODOO_VERSION -t $IMAGE -"
    else
        tar -C "$DIR/docker" -cf - . | docker build -q --build-arg "ODOO_VERSION=$ODOO_VERSION" -t "$IMAGE" - >/dev/null
        if docker run --rm -v "$SRC:/probe:ro" --entrypoint /bin/sh "$IMAGE" -c 'test -f /probe/odoo-bin' >/dev/null 2>&1; then
            SRC_MODE=mount
            echo "  the Docker daemon sees $SRC — bind-mount mode"
        else
            SRC_MODE=copy
            echo "  the Docker daemon cannot see $SRC (snap-confined Docker, remote daemon, /tmp...) — copy mode"
        fi
    fi
fi

# ── 6. register the project with the factory ────────────────────────────────────────────────
step "registering project '$PROJECT'"
if [ "$DRY" = yes ]; then
    echo "  [dry-run] $DIR/bin/of-odoo register $PROJECT $SRC --base $ODOO_VERSION --forge $FORGE${GITHUB_OWNER:+ --repo $GITHUB_OWNER/odoo}"
else
    OF_ODOO_SRC_MODE=$SRC_MODE OF_ODOO_IMAGE=$IMAGE OF_ODOO_HTTP_PORT=$ODOO_PORT \
        "$DIR/bin/of-odoo" register "$PROJECT" "$SRC" --base "$ODOO_VERSION" --forge "$FORGE" \
        ${GITHUB_OWNER:+--repo "$GITHUB_OWNER/odoo"}
fi

step "done"
cat <<EOF
  Next:
    export PATH="$DIR/bin:\$PATH"
    of-odoo doctor            # the factory's own checklist for '$PROJECT'
    of-odoo prove             # runs setup + validate once, asks the agent one question
    of-odoo up                # Odoo at http://localhost:$ODOO_PORT (admin / admin)
    of-odoo factory up        # engine, worker and panel at http://127.0.0.1:$PANEL_PORT
  Then write a card (examples/cards/01-x-hello.md) — see README.md.
EOF
