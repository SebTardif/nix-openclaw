#!/bin/sh
set -eu

script="${OPENCLAW_WORKSPACE_MATERIALIZER:?OPENCLAW_WORKSPACE_MATERIALIZER is required}"

work="$(mktemp -d)"
stale="$work/workspace/skills/stale"
current="$work/workspace/AGENTS.md"

mkdir -p "$stale" "$work/src"
printf 'stale\n' > "$stale/SKILL.md"
printf 'old-doc\n' > "$current"
printf '%s\n%s\n' "$stale" "$current" > "$work/manifest"
printf 'new-doc\n' > "$work/src/AGENTS.md"
printf '%s\t%s\n' "$work/src/AGENTS.md" "$current" > "$work/source.tsv"

"$script" "$work/manifest" "$work/source.tsv"

test ! -e "$stale"
test -f "$current"
grep -q 'new-doc' "$current"
grep -Fxq "$current" "$work/manifest"
! grep -Fxq "$stale" "$work/manifest"

empty_work="$(mktemp -d)"
empty_stale="$empty_work/workspace/skills/stale"
empty_secret="$empty_work/outside-secret"

mkdir -p "$empty_stale"
printf 'stale\n' > "$empty_stale/SKILL.md"
printf 'keep-empty-desired-f002\n' > "$empty_secret"
printf '%s\n%s\n' "$empty_stale" "$empty_secret" > "$empty_work/manifest"
: > "$empty_work/source.tsv"

"$script" "$empty_work/manifest" "$empty_work/source.tsv"

test ! -e "$empty_stale"
test -f "$empty_secret"
grep -q 'keep-empty-desired-f002' "$empty_secret"
test ! -s "$empty_work/manifest"

poison_work="$(mktemp -d)"
poison_current="$poison_work/workspace/AGENTS.md"
poison_secret="$poison_work/outside-secret"

mkdir -p "$poison_work/workspace" "$poison_work/src"
printf 'unique-secret-content-f002\n' > "$poison_secret"
printf 'old-doc\n' > "$poison_current"
printf '%s\n%s\n' "$poison_secret" "$poison_current" > "$poison_work/manifest"
printf 'new-doc\n' > "$poison_work/src/AGENTS.md"
printf '%s\t%s\n' "$poison_work/src/AGENTS.md" "$poison_current" > "$poison_work/source.tsv"

"$script" "$poison_work/manifest" "$poison_work/source.tsv"

test -f "$poison_secret"
grep -q 'unique-secret-content-f002' "$poison_secret"
test -f "$poison_current"
grep -q 'new-doc' "$poison_current"

dotdot_work="$(mktemp -d)"
dotdot_current="$dotdot_work/workspace/AGENTS.md"
dotdot_secret="$dotdot_work/outside-dotdot"
dotdot_escape="$dotdot_work/workspace/../outside-dotdot"

mkdir -p "$dotdot_work/workspace" "$dotdot_work/src"
printf 'keep-dotdot-f002\n' > "$dotdot_secret"
printf 'old-doc\n' > "$dotdot_current"
printf '%s\n%s\n' "$dotdot_escape" "$dotdot_current" > "$dotdot_work/manifest"
printf 'new-doc\n' > "$dotdot_work/src/AGENTS.md"
printf '%s\t%s\n' "$dotdot_work/src/AGENTS.md" "$dotdot_current" > "$dotdot_work/source.tsv"

"$script" "$dotdot_work/manifest" "$dotdot_work/source.tsv"

test -f "$dotdot_secret"
grep -q 'keep-dotdot-f002' "$dotdot_secret"
test -f "$dotdot_current"
grep -q 'new-doc' "$dotdot_current"

link_work="$(mktemp -d)"
link_current="$link_work/workspace/AGENTS.md"
link_secret="$link_work/outside-via-link"
link_poison="$link_work/workspace/poison-link"

mkdir -p "$link_work/workspace" "$link_work/src"
printf 'keep-via-link-f002\n' > "$link_secret"
ln -s "$link_secret" "$link_poison"
printf 'old-doc\n' > "$link_current"
printf '%s\n%s\n' "$link_poison" "$link_current" > "$link_work/manifest"
printf 'new-doc\n' > "$link_work/src/AGENTS.md"
printf '%s\t%s\n' "$link_work/src/AGENTS.md" "$link_current" > "$link_work/source.tsv"

"$script" "$link_work/manifest" "$link_work/source.tsv"

test -f "$link_secret"
grep -q 'keep-via-link-f002' "$link_secret"
test -f "$link_current"
grep -q 'new-doc' "$link_current"
