#!/bin/sh
# odoo-validate.sh — the manifest's setup:/validate:/test_inventory: commands for an Odoo fork.
#
#   odoo-validate.sh setup     PROJECT   Docker reachable, dev image present, Postgres up
#   odoo-validate.sh test      PROJECT   Odoo tests of the addons this change touches, only
#   odoo-validate.sh lint      PROJECT   syntax / manifest / access-file checks on changed files
#   odoo-validate.sh security  PROJECT   credentials added by the change (changed files only)
#   odoo-validate.sh inventory PROJECT   one test id per line (the manifest's test_inventory)
#
# Runs in the job's worktree (the current directory). "This change" = the working tree, committed
# or not, against the merge-base with the project's base branch. Tests run inside the dev image
# against the project's compose Postgres, in a throwaway database that is dropped afterwards, so
# the host needs no Odoo Python dependencies.
set -eu

sub=${1:?usage: odoo-validate.sh setup|test|lint|inventory PROJECT}
project=${2:?usage: odoo-validate.sh $sub PROJECT}
OF_ODOO_DIR=${OF_ODOO_DIR:-$(cd "$(dirname "$0")/.." && pwd)}
# shellcheck disable=SC1091
. "$OF_ODOO_DIR/lib/common.sh"
of_load_config
of_load_project "$project"
PY="$OF_ODOO_DIR/core/.venv/bin/python"

WT=$(git rev-parse --show-toplevel)
cd "$WT"

base_commit() {
    git merge-base HEAD "$OF_ODOO_BASE" 2>/dev/null || git rev-parse "$OF_ODOO_BASE"
}

# Paths changed since commit $1: committed, staged, unstaged and untracked.
changed_since() {
    { git diff --name-only "$1"; git ls-files --others --exclude-standard; } | sort -u
}

# The module directory (holding __manifest__.py) a path belongs to, or nothing.
module_dir() {
    _d=$(dirname "$1")
    while [ "$_d" != . ] && [ "$_d" != / ]; do
        if [ -f "$_d/__manifest__.py" ]; then printf '%s\n' "$_d"; return 0; fi
        _d=$(dirname "$_d")
    done
    return 1
}

# Changed paths that are not code: they need no test run.
is_inert() {
    case $1 in
        .openfactory/*|.github/*|doc/*|*.md|*.rst|*.txt|.gitignore|.git*) return 0 ;;
    esac
    return 1
}

# Splits a path list (stdin) into module dirs (MODS_DIRS) and non-module code paths (LOOSE).
classify() {
    MOD_DIRS="" LOOSE=""
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        is_inert "$f" && continue
        if m=$(module_dir "$f"); then
            case " $MOD_DIRS " in *" $m "*) ;; *) MOD_DIRS="$MOD_DIRS $m" ;; esac
        else
            case $f in
                # a file of a module this change deleted outright: nothing left to test
                custom_addons/*/*|addons/*/*|odoo/addons/*/*) [ -e "$f" ] || continue ;;
            esac
            LOOSE="$LOOSE $f"
        fi
    done
}

cmd_setup() {
    command -v docker >/dev/null 2>&1 || of_die "docker is not on PATH — validation runs Odoo in Docker"
    docker info >/dev/null 2>&1 || of_die "the Docker daemon does not answer (docker info)"
    of_ensure_image
    of_compose up -d db >/dev/null 2>&1 || of_compose up -d db
    of_wait_db
    of_say "setup: image $OF_ODOO_IMAGE present, postgres up ($OF_ODOO_COMPOSE_PROJECT)"
}

cmd_test() {
    base=$(base_commit)
    classify <<EOF
$(changed_since "$base")
EOF
    mods=""
    for d in $MOD_DIRS; do
        [ -f "$d/__manifest__.py" ] || continue   # a module this change deleted: nothing to run
        mods="${mods:+$mods,}$(basename "$d")"
    done
    if [ -n "$LOOSE" ]; then
        of_say "changed outside any addon:$LOOSE"
        of_say "→ also running ${OF_ODOO_FRAMEWORK_TESTS:-base} tests (OF_ODOO_FRAMEWORK_TESTS)"
        mods="${mods:+$mods,}${OF_ODOO_FRAMEWORK_TESTS:-base}"
    fi
    mods=$(printf '%s' "$mods" | tr ',' '\n' | awk 'NF && !seen[$0]++' | paste -sd, -)
    if [ -z "$mods" ]; then
        of_say "validate: no Odoo addon touched since $(git rev-parse --short "$base") — nothing to test"
        return 0
    fi
    of_say "validate: testing $mods (changed since $(git rev-parse --short "$base") on $OF_ODOO_BASE)"

    cmd_setup >/dev/null
    net="${OF_ODOO_COMPOSE_PROJECT}_default"
    db="ofv_$(date +%s)_$$"
    tmp=$(mktemp -d)
    trap 'of_compose exec -T db dropdb -U odoo --if-exists "$db" >/dev/null 2>&1 || true; rm -rf "$tmp"' EXIT

    mode=$OF_ODOO_SRC_MODE
    if [ "$mode" = mount ] && ! of_daemon_sees "$WT" "$OF_ODOO_IMAGE"; then
        of_say "(the Docker daemon cannot see $WT — copy mode for this run)"
        mode=copy
    fi
    set +e
    if [ "$mode" = mount ]; then
        docker run --rm --network "$net" -v "$WT:/opt/odoo/src:ro" \
            --entrypoint /usr/local/bin/of-odoo-test "$OF_ODOO_IMAGE" "$db" "$mods" none
        rc=$?
    else
        # COPY MODE: the project's source volume holds some commit C of this repository; stream
        # in what differs from C — whole module directories, overlaid ahead of the volume's on
        # the addons path, or (when code outside any addon changed) every changed file over a
        # private copy of the tree.
        vc=$(docker run --rm -v "${OF_ODOO_COMPOSE_PROJECT}_src:/src" --entrypoint /bin/sh \
                "$OF_ODOO_IMAGE" -c 'cat /src/.of-commit 2>/dev/null' || true)
        if [ -z "$vc" ] || ! git cat-file -e "$vc^{commit}" 2>/dev/null; then
            of_sync_volume "$WT" "$base"; vc=$(git rev-parse "$base")
        fi
        classify <<EOF
$(changed_since "$vc")
EOF
        how=overlay
        for d in $MOD_DIRS; do
            case $d in custom_addons/*/*|addons/*/*|odoo/addons/*/*) how=full ;;
                       custom_addons/*|addons/*|odoo/addons/*) ;; *) how=full ;; esac
        done
        [ -z "$LOOSE" ] || how=full
        : > "$tmp/.of-deleted"
        if [ "$how" = full ]; then
            files=""
            # (Odoo paths carry no whitespace; word splitting here is deliberate)
            for f in $(changed_since "$vc"); do
                if [ -e "$f" ]; then files="$files $f"; else printf '%s\n' "$f" >> "$tmp/.of-deleted"; fi
            done
            # shellcheck disable=SC2086
            tar -cf - $files -C "$tmp" .of-deleted
        else
            dirs=""
            for d in $MOD_DIRS; do [ -d "$d" ] && dirs="$dirs $d"; done
            # shellcheck disable=SC2086
            tar -cf - $dirs -C "$tmp" .of-deleted
        fi | docker run -i --rm --network "$net" -v "${OF_ODOO_COMPOSE_PROJECT}_src:/opt/odoo/src:ro" \
                --entrypoint /usr/local/bin/of-odoo-test "$OF_ODOO_IMAGE" "$db" "$mods" "$how"
        rc=$?
    fi
    set -e
    return $rc
}

# A credential this change adds (changed files only — the base tree is Odoo's, with its test keys).
cmd_security() {
    base=$(base_commit)
    hits=""
    for f in $(changed_since "$base"); do
        [ -f "$f" ] || continue
        case $f in */tests/*|*/test/*) continue ;; esac   # fixtures: test keys are what tests use
        h=$(grep -nIE -e '-----BEGIN ([A-Z]+ )?PRIVATE KEY-----' \
                -e '(^|[^0-9A-Za-z+/])(AKIA|ASIA)[0-9A-Z]{16}' \
                -e 'gh[pousr]_[0-9A-Za-z]{36}|github_pat_[0-9A-Za-z_]{22,}' \
                -e 'xox[abprs]-[0-9A-Za-z-]{10,}|glpat-[0-9A-Za-z_-]{20}' \
                -e '(^|[^0-9A-Za-z+/])AIza[0-9A-Za-z_-]{35}' \
                -e 'sk-(ant-)?[0-9A-Za-z_-]{32,}' "$f" 2>/dev/null | sed "s|^|$f:|" || true)
        [ -z "$h" ] || hits="$hits$h
"
    done
    if [ -n "$hits" ]; then
        printf '%s' "$hits"
        of_say "security: a credential is added in the lines above — remove it (and rotate it)"
        return 1
    fi
    of_say "security: no credential in the changed files"
}

case $sub in
    setup) cmd_setup ;;
    security) cmd_security ;;
    test) cmd_test ;;
    lint) base=$(base_commit); changed_since "$base" | "$PY" "$OF_ODOO_DIR/lib/odoo_lint.py" "$OF_ODOO_SERIES" ;;
    inventory) "$PY" "$OF_ODOO_DIR/lib/odoo_test_inventory.py" . ;;
    *) of_die "unknown subcommand $sub (setup|test|lint|security|inventory)" ;;
esac
