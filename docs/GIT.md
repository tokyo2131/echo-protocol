# Git

## Global configuration (`scripts/15-git-config.sh`)

Set for the admin user from `.env`'s `GIT_USER_NAME`/`GIT_USER_EMAIL`:

```
git config --global user.name  "$GIT_USER_NAME"
git config --global user.email "$GIT_USER_EMAIL"
git config --global init.defaultBranch main
git config --global pull.rebase false
git config --global core.editor vim
git config --global credential.helper store
```

## Git LFS

Installed in stage 06 (`git-lfs` package) and initialized (`git lfs
install --skip-repo`) in both stage 13 and stage 15 — safe to run twice,
idempotent. Per-repo, still run `git lfs install` inside the repo (or
`git lfs track "*.psd"` etc.) as usual; the global init only registers
the LFS smudge/clean filters.

## Outbound SSH authentication to GitHub/GitLab

`scripts/15-git-config.sh` generates a dedicated Ed25519 keypair at
`~<admin>/.ssh/id_ed25519_git` — **separate from** the key you use to
log into the server (see `docs/SSH.md`). It also writes
`~<admin>/.ssh/config` entries pinning `github.com`/`gitlab.com` to that
key with `IdentitiesOnly yes`, and pre-seeds `known_hosts` via
`ssh-keyscan` so the first `git clone` doesn't hang on a host-key
prompt.

After provisioning, register the key:

```
cat ~<admin>/.ssh/id_ed25519_git.pub
```

Add it under GitHub → Settings → SSH and GPG keys (or GitLab's
equivalent). Until you do, `git clone git@github.com:...` from the
server will fail with a permission error — HTTPS clones with a personal
access token work regardless.

## GitHub CLI

`gh` is installed in stage 13. Authenticate once per admin session with
`gh auth login` (interactive) if you want `gh pr create`, `gh repo
clone`, etc. — separate from the SSH key above, which only covers plain
git operations.
