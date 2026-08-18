# Shared harness for the shell unit tests. Each *.test.sh sources this and gets
# pass/fail counting plus the check helpers. Usage from a test file:
#
#   script="${1:?usage: x.test.sh <script> <lib>}"
#   . "${2:?}"
#   check_eq "description" "expected" "$(run_script args...)"
#   finish
#
# `finish` prints the tally and returns nonzero if anything failed, which is
# what makes the suite load-bearing rather than decorative.

pass=0
fail=0

_report() { # <ok|no> <description> [expected] [actual]
  if [ "$1" = ok ]; then
    pass=$((pass + 1))
    echo "ok   - $2"
  else
    fail=$((fail + 1))
    echo "FAIL - $2"
    [ $# -ge 3 ] && echo "         expected: [$3]"
    [ $# -ge 4 ] && echo "         got:      [$4]"
  fi
}

# check_eq <description> <expected> <actual>
check_eq() {
  if [ "$2" = "$3" ]; then _report ok "$1"; else _report no "$1" "$2" "$3"; fi
}

# check_exit <description> <expected-exit> <command...>
check_exit() {
  _desc="$1"
  _want="$2"
  shift 2
  "$@" >/dev/null 2>&1
  _got=$?
  if [ "$_got" = "$_want" ]; then
    _report ok "$_desc"
  else
    _report no "$_desc" "exit $_want" "exit $_got"
  fi
}

finish() {
  echo "---"
  echo "$pass passed, $fail failed"
  [ "$fail" -eq 0 ]
}
