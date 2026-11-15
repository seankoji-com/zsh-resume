# shellcheck shell=bash disable=all
Describe 'worktree discovery timeout'
    It 'bounds stalled discovery and keeps the root'
    When run python3 "$SHELLSPEC_PROJECT_ROOT/spec/worktree_timeout_test.py"
    The status should be success
    The stderr should include 'OK'
    End
End
