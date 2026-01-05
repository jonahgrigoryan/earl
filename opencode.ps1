# OpenCode wrapper script for Windows Terminal
# This script launches OpenCode in Windows Terminal for proper TUI rendering

$opencodeArgs = $args -join ' '
Start-Process wt.exe -ArgumentList "opencode $opencodeArgs" -NoNewWindow
