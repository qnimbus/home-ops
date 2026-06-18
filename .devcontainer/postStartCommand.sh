#!/bin/bash

# Activate mise for the current session (provides task, kubectl, etc. which are not in default PATH)
eval "$(~/.local/bin/mise activate bash)"

# Refresh agent skills in the background. sleep 15 gives the Claude Code CLI time to finish its
# cold-start initialization; timeout 120s guards against hanging without a TTY.
# validate:update runs independently so a skills-update failure never blocks asset sync.
(sleep 15 && timeout 120 claude skills update </dev/null 2>&1 || true) &
disown
(task validate:update) &
disown
