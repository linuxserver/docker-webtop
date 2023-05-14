#! /bin/bash



for branch in rebase-fedora-i3 rebase-fedora-icewm rebase-fedora-kde rebase-fedora-mate rebase-fedora-xfce debian-i3 debian-icewm debian-kde debian-mate debian-openbox debian-xfce; do
  sleep 600
  git push origin $branch
done
