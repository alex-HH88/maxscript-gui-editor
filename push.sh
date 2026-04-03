#!/bin/bash
source "$(dirname "$0")/.env"
git remote set-url origin https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${GITHUB_REPO}.git
git push "$@"
