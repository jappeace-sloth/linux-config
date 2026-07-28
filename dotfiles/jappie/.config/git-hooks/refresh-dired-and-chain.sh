#!/bin/sh
# Global git hook. core.hooksPath in .gitconfig points at this
# directory, and every client-side hook name in here is a symlink to
# this script. Two jobs:
#
# 1. After a hook that changed the worktree (pull, checkout, rebase,
#    am), tell the emacs daemon to refresh its dired/dirvish listings
#    (jappie-dired-revert-all in emacs/emacs.el), so the file manager
#    shows the new files without a manual gr.
# 2. Chain to the repository's own hook of the same name. With
#    core.hooksPath set, git looks ONLY in this directory, which would
#    otherwise silently disable every repo-local hook (husky installs,
#    .git/hooks scripts). That is also why ALL client-side hook names
#    are symlinked here, not just the post-* ones: a name missing from
#    this directory is a repo-local hook that never runs again.
#
# Decision: a global core.hooksPath calling emacsclient was chosen to
# refresh emacs on git changes. Alternatives considered: emacs-side
# polling (global-auto-revert-non-file-buffers) stats every listing on
# a timer and lags up to 5s; init.templateDir only affects freshly
# cloned repos; magit-post-refresh-hook misses terminal git entirely.

hook_name=$(basename "$0")

# Chain BEFORE refreshing: a repo-local hook may itself create files
# (build artifacts, generated code) and those should be in the listing
# emacs re-reads. Its exit status is preserved, that is what makes the
# pre-* hooks able to abort the git command.
# $GIT_DIR/hooks, NOT `git rev-parse --git-path hooks`: the latter
# honors core.hooksPath and would loop back into this very script.
repo_hooks="$(git rev-parse --git-dir 2>/dev/null)/hooks"
chain_status=0
if [ -x "$repo_hooks/$hook_name" ]; then
    "$repo_hooks/$hook_name" "$@"
    chain_status=$?
fi

case "$hook_name" in
    post-merge|post-checkout|post-rewrite|post-applypatch)
        # Best effort: no running daemon (or no emacsclient on PATH) is
        # a normal situation and must never fail the git command.
        emacsclient --quiet --eval '(jappie-dired-revert-all)' >/dev/null 2>&1 || true
        ;;
esac

exit "$chain_status"
