# shellcheck shell=sh
# lib/common.sh — shared by bin/of-odoo, lib/odoo-validate.sh and install.sh.
#
# Sourced, never executed. Expects OF_ODOO_DIR to be set to the install directory.

of_say()  { printf '%s\n' "$*"; }
of_warn() { printf 'of-odoo: %s\n' "$*" >&2; }
of_die()  { printf 'of-odoo: %s\n' "$*" >&2; exit 1; }

# The install's own config (ports, real HOME, default project).
of_load_config() {
    [ -n "${OF_ODOO_DIR:-}" ] || of_die "OF_ODOO_DIR is not set"
    [ -f "$OF_ODOO_DIR/of-odoo.env" ] || of_die "$OF_ODOO_DIR/of-odoo.env is missing — is this an of-odoo install? (run install.sh)"
    # shellcheck disable=SC1091
    . "$OF_ODOO_DIR/of-odoo.env"
}

# One registered Odoo project: its fork checkout, base branch, compose project, image...
# $1 = project name (defaults to the install's default project).
of_load_project() {
    _p=${1:-${OF_ODOO_PROJECT:-$OF_ODOO_DEFAULT_PROJECT}}
    [ -f "$OF_ODOO_DIR/projects/$_p.env" ] || of_die "no project '$_p' in this install (see: of-odoo projects)"
    # shellcheck disable=SC1090
    . "$OF_ODOO_DIR/projects/$_p.env"
    OF_ODOO_PROJECT=$_p
}

# THE ISOLATION. openfactory-core keeps every piece of operator state under `$HOME/.openfactory`
# (`namespace.operator_path`) and always loads `~/.openfactory/env` (cli.py `_HOST_ENV`); there is
# no OPENFACTORY_HOME. So this install runs the platform with HOME pointed at its own directory,
# and hands back exactly the pieces of the real HOME the tools need: the coding agent's login
# (a symlink, made by install.sh), git identity, Docker and gh configuration.
of_platform_env() {
    _real=${OF_ODOO_REAL_HOME:-$HOME}
    export OF_ODOO_REAL_HOME="$_real"
    export HOME="$OF_ODOO_DIR/home"
    if [ -d "$_real/.docker" ] && [ -z "${DOCKER_CONFIG:-}" ]; then export DOCKER_CONFIG="$_real/.docker"; fi
    if [ -d "$_real/.config/gh" ] && [ -z "${GH_CONFIG_DIR:-}" ]; then export GH_CONFIG_DIR="$_real/.config/gh"; fi
    # Explicit beats every file core reads (load_dotenv never overrides a set variable).
    export TEMPORAL_ADDRESS="127.0.0.1:$OF_TEMPORAL_PORT"
    export TEMPORAL_UI_URL="http://127.0.0.1:$OF_TEMPORAL_UI_PORT"
    export OPENFACTORY_PANEL_URL="http://127.0.0.1:$OF_PANEL_PORT"
    export OPENFACTORY_GUIDELINES_DIR="$OF_ODOO_DIR/guidelines"
    export OF_ODOO_DIR
    PATH="$OF_ODOO_DIR/core/.venv/bin:$OF_ODOO_DIR/bin:$PATH"
    export PATH
}

of_openfactory() {
    ( of_platform_env && cd "$OF_ODOO_DIR" && exec openfactory "$@" )
}

# Docker compose for one project. Never publishes Postgres; Odoo's port is OF_ODOO_HTTP_PORT.
of_compose() {
    # The file goes through a PIPE for the same reason the build context does: a snap-confined
    # docker CLI cannot open files under /tmp — not even as a redirected stdin, which it reopens
    # by path — and nothing here should care where the install lives.
    cat "$OF_ODOO_DIR/docker/compose.yaml" |
        OF_ODOO_IMAGE=$OF_ODOO_IMAGE OF_ODOO_HTTP_PORT=$OF_ODOO_HTTP_PORT \
        OF_ODOO_SRC_MOUNT=$(of_src_mount) \
        docker compose -p "$OF_ODOO_COMPOSE_PROJECT" -f - "$@"
}

# Bind mount (the daemon sees the checkout) or the named volume (copy mode — snap-confined Docker,
# a remote daemon, a checkout under /tmp).
of_src_mount() {
    if [ "${OF_ODOO_SRC_MODE:-mount}" = mount ]; then printf '%s' "$OF_ODOO_SRC"
    else printf 'src'; fi   # the compose volume `src`, i.e. <compose project>_src
}

# Build the dev image from the install's docker/ directory. The context goes over stdin, so it
# works whatever the daemon can or cannot see of this filesystem.
of_build_image() {
    _base=$1 _tag=$2
    tar -C "$OF_ODOO_DIR/docker" -cf - . |
        docker build -q --build-arg "ODOO_VERSION=$_base" -t "$_tag" - >/dev/null
}

# Can the Docker daemon see this host directory? (Probes for odoo-bin inside it.)
of_daemon_sees() {
    docker run --rm -v "$1:/probe:ro" --entrypoint /bin/sh "$2" -c 'test -f /probe/odoo-bin' >/dev/null 2>&1
}

# Copy mode: put commit $2 of checkout $1 into the project's source volume, unless it is there.
of_sync_volume() {
    _repo=$1 _commit=$(git -C "$1" rev-parse "$2^{commit}") || return 1
    _vol="${OF_ODOO_COMPOSE_PROJECT}_src"
    # created with compose's own labels, so `docker compose` adopts it as the stack's `src`
    docker volume inspect "$_vol" >/dev/null 2>&1 || docker volume create \
        --label "com.docker.compose.project=$OF_ODOO_COMPOSE_PROJECT" \
        --label com.docker.compose.volume=src "$_vol" >/dev/null
    _have=$(docker run --rm -v "$_vol:/src" --entrypoint /bin/sh "$OF_ODOO_IMAGE" -c 'cat /src/.of-commit 2>/dev/null' || true)
    [ "$_have" = "$_commit" ] && return 0
    of_say "syncing $(git -C "$_repo" rev-parse --short "$_commit") into volume $_vol (copy mode)..."
    git -C "$_repo" archive --format=tar "$_commit" |
        docker run -i --rm -u 0 -v "$_vol:/src" --entrypoint /bin/sh "$OF_ODOO_IMAGE" -c \
            "find /src -mindepth 1 -delete && tar -xf - -C /src && echo $_commit > /src/.of-commit && chown -R odoo /src"
}

of_ensure_image() {
    if ! docker image inspect "$OF_ODOO_IMAGE" >/dev/null 2>&1; then
        of_say "building $OF_ODOO_IMAGE (FROM odoo:$OF_ODOO_SERIES)..."
        of_build_image "$OF_ODOO_SERIES" "$OF_ODOO_IMAGE"
    fi
}

of_wait_db() {
    _i=0
    until of_compose exec -T db pg_isready -U odoo >/dev/null 2>&1; do
        _i=$((_i + 1)); [ $_i -lt 60 ] || of_die "postgres did not become ready"
        sleep 1
    done
}
