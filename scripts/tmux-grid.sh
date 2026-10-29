#!/bin/bash
# Usage:
#   grid 6            → 6 panes, auto-tiled
#   grid 3x4          → 12 panes (3 rows x 4 cols)
#   grid 4 "npm start" → 4 panes, each pre-filled with "npm start"
#
# If already inside tmux: splits the current window.
# If outside tmux: creates a new session and attaches.

grid() {
    local n text="${*:2}"
    case "$1" in
        ""|help|-h)
            echo "Usage: grid <N | RxC> [text]"
            echo "  grid 6            → 6 panes"
            echo "  grid 3x4          → 12 panes"
            echo "  grid 4 'npm start' → 4 panes pre-filled with text"
            return ;;
        *x*) n=$(( ${1%x*} * ${1#*x} )) ;;
        *)   n=$1 ;;
    esac

    (( n < 1 || n > 46 )) && { echo "Error: max 46 panes (got $n)" >&2; return 1; }

    if [[ -n "$TMUX" ]]; then
        for (( i = 2; i <= n; i++ )); do
            tmux split-window
            tmux select-layout tiled
        done
        tmux select-layout tiled
        if [[ -n "$text" ]]; then
            local pane_count
            pane_count=$(tmux list-panes -F '#{pane_id}' | wc -l)
            for (( i = pane_count - n; i < pane_count; i++ )); do
                tmux send-keys -t "%$i" "$text" ""
            done
        fi
    else
        local session="grid"
        tmux kill-session -t "$session" 2>/dev/null || true
        tmux new-session -d -s "$session"
        for (( i = 2; i <= n; i++ )); do
            tmux split-window -t "$session"
            tmux select-layout -t "$session" tiled
        done
        tmux select-layout -t "$session" tiled
        if [[ -n "$text" ]]; then
            local panes
            panes=$(tmux list-panes -t "$session" -F '#{pane_id}')
            while IFS= read -r pane_id; do
                tmux send-keys -t "$pane_id" "$text" ""
            done <<< "$panes"
        fi
        tmux attach -t "$session"
    fi
}

# Run if executed directly (not sourced)
if [[ -n "$ZSH_VERSION" ]]; then
    [[ "$ZSH_EVAL_CONTEXT" != *:file ]] && grid "$@"
elif [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    grid "$@"
fi
