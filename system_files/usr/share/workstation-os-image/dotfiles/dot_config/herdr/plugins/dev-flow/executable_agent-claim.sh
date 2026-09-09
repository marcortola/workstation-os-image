#!/usr/bin/env bash
# [[startup]]: make every running agent a slot the rest of the plugin can see.
#
# herdr restores a session with its agents (`[session] resume_agents_on_restore`),
# so a server start is when the gap between what is running and what is labelled
# is widest -- and it is the one moment every workspace is walked anyway. Two
# convergences, both idempotent and both no-ops on a workspace laid out since the
# labels became kinds:
#
#   a tab still called `main`      -> renamed to the agent herdr reports in it
#   two agents sharing one tab     -> the second gets a tab named after its kind
#
# What it deliberately does not do is claim a `nvim` or `term` tab that holds an
# agent. That rename takes the workspace's editor or shell away, and only a
# layout run can build the missing one back; `claim_agent_tabs` does it there,
# where the rebuild follows immediately.
#
# Never fails the startup chain. herdr runs these in order and a non-zero exit
# from one is not worth the two behind it -- window-title.sh among them.
set -uo pipefail

plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=layout-common.sh
. "$plugin_dir/layout-common.sh"

while IFS= read -r workspace; do
  [ -n "$workspace" ] || continue
  claim_legacy_agent_tabs "$workspace" || true
  claim_agent_panes "$workspace" || true
done < <(herdr_cli workspace list | jq -r '.result.workspaces[].workspace_id')

exit 0
