#!/usr/bin/env bash
# Runs a command; if it fails, puts the important error lines into one
# GitHub annotation so they are visible on the run's summary page.
set -o pipefail
"$@" 2>&1 | tee /tmp/step_output.txt
code=${PIPESTATUS[0]}
if [ "$code" -ne 0 ]; then
  msg=$(grep -E "^\s*error •|^\s*warning •|lib/.*\.dart:[0-9]+:[0-9]+: Error|Error:|What went wrong|FAILURE|Some tests failed|version solving failed|Because |Expected:|Actual:|Exception" /tmp/step_output.txt \
    | head -60 | sed 's/%/%25/g; s/\r//g' | awk 'BEGIN{ORS="%0A"} {print}')
  java=$(grep -E -A4 "\.java:[0-9]+: error|^e: .*\.kt|Unresolved reference|cannot find symbol|Missing class|ERROR: R8|ERROR:.*R8" /tmp/step_output.txt \
    | head -40 | sed 's/%/%25/g; s/\r//g' | awk 'BEGIN{ORS="%0A"} {print}')
  [ -n "$java" ] && echo "::error title=Java/Kotlin errors::${java}"
  gradle=$(grep -E -A10 "What went wrong" /tmp/step_output.txt | head -40 | sed 's/%/%25/g; s/\r//g' | awk 'BEGIN{ORS="%0A"} {print}')
  [ -n "$gradle" ] && echo "::error title=Gradle::${gradle}"
  exc=$(grep -E -A12 "EXCEPTION CAUGHT BY|overflowed by|Test failed. See exception logs above|Bad state|No element|Too many elements|Expected: |══╡" /tmp/step_output.txt \
    | grep -vE "^\s*$" | head -120 | sed 's/%/%25/g; s/\r//g' | awk 'BEGIN{ORS="%0A"} {print}')
  [ -n "$exc" ] && echo "::error title=Exceptions::${exc}"
  [ -z "$msg" ] && msg=$(tail -40 /tmp/step_output.txt | sed 's/%/%25/g; s/\r//g' | awk 'BEGIN{ORS="%0A"} {print}')
  echo "::error title=Step failed::${msg}"
  # Full output to the ci-logs branch, so it can be read without the log viewer.
  if [ -n "$GITHUB_WORKSPACE" ]; then
    (
      d=$(mktemp -d) && cd "$d" && git init -q && git checkout -q -b ci-logs &&
      sed 's/\x1b\[[0-9;]*m//g' /tmp/step_output.txt > log.txt && git add log.txt &&
      git -c user.name=ci -c user.email=ci@localhost commit -qm "log ${GITHUB_RUN_ID}" &&
      hdr=$(git -C "$GITHUB_WORKSPACE" config --get http.https://github.com/.extraheader) &&
      git -c http.extraheader="$hdr" push -qf "$(git -C "$GITHUB_WORKSPACE" remote get-url origin)" ci-logs
    ) || echo "could not save the log"
  fi
fi
exit "$code"
