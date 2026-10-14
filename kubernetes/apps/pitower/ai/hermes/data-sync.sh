#!/bin/sh
# data-sync sidecar: keeps a writable clone of swibrow/hermes at /opt/data/hermes-data,
# commits and pushes what hermes writes under data/, pulls edits made elsewhere, and
# re-applies cron/jobs.yaml when it changes on main. The push token lives only in this
# container, so the agent itself cannot push to the repo.
set -u

repo=/opt/data/hermes-data
jobs=/opt/hermes-repo/current/cron/jobs.yaml
git_() {
  git -c credential.helper=/etc/git-sync/git-credential-github \
    -c user.name=hermes -c user.email=hermes@wibrow.dev "$@"
}

applied=$(sha256sum "$jobs" | cut -d' ' -f1)

while true; do
  if [ ! -d "$repo/.git" ] && ! git_ clone -q https://github.com/swibrow/hermes.git "$repo"; then
    echo "data-sync: clone failed, retrying"
    sleep 60
    continue
  fi
  git_ -C "$repo" add -A data
  git_ -C "$repo" diff --cached --quiet || git_ -C "$repo" commit -q -s -m "chore(data): sync hermes state"
  if git_ -C "$repo" pull -q --rebase origin main; then
    # The clone is on the agent-writable PVC: never push a commit that reaches outside data/.
    outside=$(git_ -C "$repo" diff --name-only origin/main HEAD | grep -v '^data/')
    if [ -n "$outside" ]; then
      echo "data-sync: refusing to push, local commits touch files outside data/: $outside"
    else
      git_ -C "$repo" push -q origin HEAD:main || echo "data-sync: push failed"
    fi
  else
    git_ -C "$repo" rebase --abort
    echo "data-sync: rebase onto origin/main failed, left local commits for the next round"
  fi

  current=$(sha256sum "$jobs" | cut -d' ' -f1)
  if [ "$current" != "$applied" ] &&
    (cd /opt/hermes && .venv/bin/python /opt/hermes-repo/current/cron/sync.py "$jobs"); then
    applied=$current
  fi
  sleep 300
done
