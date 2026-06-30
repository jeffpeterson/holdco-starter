#!/usr/bin/env bash
#
# bin/lib/operator-gate.sh — the shared "is this operator safe to act on RIGHT
# NOW?" gate, factored out of bin/clear-watch so EVERY fleet action (cost-based
# auto-/clear, rolling restart, /compact, an injected prompt) reuses ONE
# definition of "safe" instead of re-deriving it. Source it; it defines functions
# only — no side effects, no global state.
#
# The gate's facts:
#   - the holdco SUPERVISOR is hard-excluded (never act on the session running this)
#   - the operator must have a LIVE tmux pane whose cwd matches (else not running)
#   - the pane must be QUIET past the ~300s cache TTL (so we forfeit no warm cache
#     and a just-delivered nudge/mail defers the action)
#   - the git tree must be CLEAN (never risk uncommitted work)
#   - the venture may OPT OUT via `<key>: false` in ventures/<id>.md
#
# Functions:
#   og_panes_snapshot                  one tmux snapshot of all live panes
#   og_field KEY FILE                  read KEY=VALUE from a usage cache file
#   og_resolve_pane CWD PANES          → "<pane_id> <activity_epoch>" or empty (rc 1)
#   og_is_supervisor LABEL BASE        rc 0 if this is the holdco supervisor
#   og_quiet_secs NOW ACTIVITY         seconds since pane activity, or "?" if unknown
#   og_tree_dirty CWD                  rc 0 if the repo has uncommitted changes
#   og_opt_out REPO_ROOT BASE [KEY]    rc 0 if ventures/<base>.md has KEY: false
#   og_safe_to_act LABEL BASE CWD PANE QUIET COLD_AFTER REPO_ROOT [KEY]
#                                      rc 0 (silent) when safe; else prints a
#                                      one-word skip-reason and returns 1
#
# clear-watch uses the SMALL predicates directly (not og_safe_to_act) so it can
# interleave its cost-specific gates (no-ctx-tokens / below-ctx-floor /
# savings-below-min) at the right points and keep its log lines byte-for-byte
# identical. operator-roll uses the og_safe_to_act aggregate. The supervisor name
# is OG_SUPERVISOR (default holdco); the opt-out key defaults to auto_clear.

# A snapshot of live panes: "<pane_id> <window_activity_epoch> <pane_current_path>".
# Captured once per tick so we don't shell out per cache file.
og_panes_snapshot() {
	tmux list-panes -a -F '#{pane_id} #{window_activity} #{pane_current_path}' 2>/dev/null
}

# Read one KEY from a cache file's KEY=VALUE lines.
og_field() { sed -n "s/^$1=//p" "$2" 2>/dev/null | head -1; }

# Print "<pane_id> <window_activity>" for the first live pane whose cwd matches,
# else nothing (empty output + rc 1) — meaning the operator isn't running.
og_resolve_pane() {
	local cwd="$1" panes="$2" p act path
	while IFS=' ' read -r p act path; do
		[ "$path" = "$cwd" ] || continue
		printf '%s %s\n' "$p" "$act"
		return 0
	done <<<"$panes"
	return 1
}

# Hard-exclude the supervisor: never act on the session that runs the gate itself.
og_is_supervisor() {
	local label="$1" base="$2" sup="${OG_SUPERVISOR:-holdco}"
	[ "$label" = "$sup" ] || [ "$base" = "$sup" ]
}

# Seconds since the pane's last activity, or "?" when activity is unreadable.
og_quiet_secs() {
	local now="$1" activity="$2"
	if [[ "$activity" =~ ^[0-9]+$ ]]; then
		echo $((now - activity))
	else
		echo '?'
	fi
}

# rc 0 if the repo at CWD is a git work tree with uncommitted changes.
og_tree_dirty() {
	local cwd="$1"
	[ -d "$cwd" ] && git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
	[ -n "$(git -C "$cwd" status --porcelain 2>/dev/null)" ]
}

# rc 0 if ventures/<base>.md opts out via `<key>: false` (default key: auto_clear).
og_opt_out() {
	local repo_root="$1" base="$2" key="${3:-auto_clear}"
	local vf="$repo_root/ventures/$base.md"
	[ -f "$vf" ] && grep -qE "^[[:space:]]*${key}:[[:space:]]*false" "$vf"
}

# Aggregate gate for non-clear actions (restart / clear / inject). Checks the
# shared safety conditions in priority order; prints the FIRST failing reason and
# returns 1, or returns 0 silently when safe. quiet="?" (unknown activity) is
# treated as NOT-idle — conservative: never act when we can't prove the pane is cold.
og_safe_to_act() {
	local label="$1" base="$2" cwd="$3" pane="$4" quiet="$5" cold="$6" repo_root="$7" key="${8:-auto_clear}"
	if og_is_supervisor "$label" "$base"; then echo supervisor; return 1; fi
	if [ -z "$pane" ]; then echo no-live-pane; return 1; fi
	if [ "$quiet" = "?" ] || [ "$quiet" -lt "$cold" ]; then echo warm-or-active; return 1; fi
	if og_tree_dirty "$cwd"; then echo dirty-tree; return 1; fi
	if og_opt_out "$repo_root" "$base" "$key"; then echo opt-out; return 1; fi
	return 0
}
