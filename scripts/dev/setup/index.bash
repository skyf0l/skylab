#!/usr/bin/env bash

#region    prelude
set -eE

#endregion prelude

repoDir="."

cd "${repoDir}"

yarn install --frozen-lockfile && yarn run husky 2>/dev/null || true
