#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
  echo "usage: openclaw-materialize-workspace-files <state-manifest> <source-target-manifest>" >&2
  exit 1
fi

manifest="$1"
source_manifest="$2"

manifest_dir="$(dirname "$manifest")"
mkdir -p "$manifest_dir"
desired_manifest="$(mktemp)"
new_manifest="$(mktemp)"
allowed_roots="$(mktemp)"
trap 'rm -f "$desired_manifest" "$new_manifest" "$allowed_roots"' EXIT

is_bootstrap_name() {
  case "$1" in
    AGENTS.md | SOUL.md | TOOLS.md | IDENTITY.md | USER.md | HEARTBEAT.md) return 0 ;;
    *) return 1 ;;
  esac
}

# Empty, ".", or any ".." path component is never a safe delete target.
path_is_rejected() {
  p="$1"
  if [ -z "$p" ] || [ "$p" = "." ]; then
    return 0
  fi
  case "$p" in
    .. | ../* | */.. | */../*) return 0 ;;
    *) return 1 ;;
  esac
}

strip_trailing_slashes() {
  p="$1"
  while [ -n "$p" ] && [ "$p" != "/" ]; do
    case "$p" in
      */) p="${p%/}" ;;
      *) break ;;
    esac
  done
  printf '%s\n' "$p"
}

try_realpath() {
  target="$1"
  resolved=""
  if command -v realpath >/dev/null 2>&1; then
    resolved="$(realpath "$target" 2>/dev/null || true)"
    if [ -n "$resolved" ]; then
      printf '%s\n' "$resolved"
      return 0
    fi
  fi
  resolved="$(readlink -f "$target" 2>/dev/null || true)"
  if [ -n "$resolved" ]; then
    printf '%s\n' "$resolved"
    return 0
  fi
  return 1
}

# Resolve for delete checks. Symlinks use the parent real path plus the
# followed target so a link that escapes the workspace is rejected.
resolve_delete_path() {
  target="$1"
  if [ -L "$target" ]; then
    parent="$(dirname "$target")"
    parent_resolved="$(try_realpath "$parent")" || parent_resolved="$parent"
    base="$(basename "$target")"
    final="$(try_realpath "$target")" || final="$parent_resolved/$base"
    if [ -z "$final" ]; then
      link_dest="$(readlink "$target" 2>/dev/null || true)"
      case "$link_dest" in
        /*) final="$link_dest" ;;
        *) final="$parent_resolved/$link_dest" ;;
      esac
    fi
    printf '%s\n' "$final"
    return 0
  fi
  resolved="$(try_realpath "$target")" || resolved="$target"
  printf '%s\n' "$resolved"
}

is_under_root() {
  path="$(strip_trailing_slashes "$1")"
  root="$(strip_trailing_slashes "$2")"
  if [ -z "$path" ] || [ -z "$root" ] || [ "$root" = "/" ] || [ "$root" = "." ]; then
    return 1
  fi
  case "$path" in
    "$root" | "$root"/*) return 0 ;;
    *) return 1 ;;
  esac
}

path_has_workspace_component() {
  probe="$(strip_trailing_slashes "$1")"
  while [ -n "$probe" ] && [ "$probe" != "/" ] && [ "$probe" != "." ]; do
    if [ "$(basename "$probe")" = "workspace" ]; then
      return 0
    fi
    next="$(dirname "$probe")"
    if [ "$next" = "$probe" ]; then
      break
    fi
    probe="$next"
  done
  return 1
}

collect_roots_from_path() {
  target="$1"
  roots_file="$2"
  base="$(basename "$target")"
  dir="$(dirname "$target")"
  if is_bootstrap_name "$base" && [ "$dir" != "/" ] && [ "$dir" != "." ]; then
    printf '%s\n' "$dir" >>"$roots_file"
  fi
  probe="$target"
  while [ -n "$probe" ] && [ "$probe" != "/" ] && [ "$probe" != "." ]; do
    if [ "$(basename "$probe")" = "workspace" ]; then
      printf '%s\n' "$probe" >>"$roots_file"
    fi
    next="$(dirname "$probe")"
    if [ "$next" = "$probe" ]; then
      break
    fi
    probe="$next"
  done
}

path_is_allowed_for_delete() {
  old_target="$1"
  if path_is_rejected "$old_target"; then
    return 1
  fi

  resolved="$(resolve_delete_path "$old_target")"
  if path_is_rejected "$resolved"; then
    return 1
  fi
  if [ -z "$resolved" ]; then
    resolved="$old_target"
  fi

  if [ -s "$allowed_roots" ]; then
    while IFS= read -r root; do
      if [ -z "$root" ]; then
        continue
      fi
      root_resolved="$(try_realpath "$root")" || root_resolved="$root"
      if is_under_root "$resolved" "$root" || is_under_root "$resolved" "$root_resolved"; then
        return 0
      fi
    done <"$allowed_roots"
    return 1
  fi

  # Uninstall (empty desired): only workspace-shaped paths, never an
  # arbitrary old target such as $HOME/Documents or a poisoned secret.
  if path_has_workspace_component "$resolved" || path_has_workspace_component "$old_target"; then
    return 0
  fi
  base="$(basename "$resolved")"
  dir="$(dirname "$resolved")"
  if is_bootstrap_name "$base"; then
    if [ "$(basename "$dir")" = "workspace" ] || path_has_workspace_component "$dir"; then
      return 0
    fi
  fi
  return 1
}

copy_path() {
  source="$1"
  target="$2"

  if [ -e "$target" ] || [ -L "$target" ]; then
    chmod -R u+w "$target" 2>/dev/null || true
    rm -rf "$target"
  fi
  mkdir -p "$(dirname "$target")"

  if [ -d "$source" ]; then
    cp -RL "$source" "$target"
  else
    cp -L "$source" "$target"
  fi

  printf '%s\n' "$target" >>"$new_manifest"
}

while IFS="$(printf '\t')" read -r source target; do
  if [ -n "$source" ] && [ -n "$target" ]; then
    printf '%s\n' "$target" >>"$desired_manifest"
  fi
done <"$source_manifest"

sort -u "$desired_manifest" -o "$desired_manifest"

if [ -s "$desired_manifest" ]; then
  while IFS= read -r desired_target; do
    if [ -n "$desired_target" ]; then
      collect_roots_from_path "$desired_target" "$allowed_roots"
    fi
  done <"$desired_manifest"
  sort -u "$allowed_roots" -o "$allowed_roots"
fi

if [ -f "$manifest" ]; then
  while IFS= read -r old_target; do
    if [ -n "$old_target" ] && ! grep -Fxq "$old_target" "$desired_manifest"; then
      if [ -e "$old_target" ] || [ -L "$old_target" ]; then
        if path_is_allowed_for_delete "$old_target"; then
          chmod -R u+w "$old_target" 2>/dev/null || true
          rm -rf "$old_target"
        else
          echo "openclaw-materialize-workspace-files: refusing to delete path outside workspace roots: $old_target" >&2
        fi
      fi
    fi
  done <"$manifest"
fi

while IFS="$(printf '\t')" read -r source target; do
  if [ -n "$source" ] && [ -n "$target" ]; then
    copy_path "$source" "$target"
  fi
done <"$source_manifest"

sort -u "$new_manifest" >"$manifest"
