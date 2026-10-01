#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
log_dir="$(mktemp -d "${TMPDIR:-/tmp}/ec2-service-tests.XXXXXX")"
trap 'rm -rf "$log_dir"' EXIT

terraform fmt -check -recursive
for directory in . modules/ec2 modules/alb examples/*; do
  printf '\nValidating %s\n' "$directory"
  terraform -chdir="$directory" init -backend=false -input=false -no-color
  terraform -chdir="$directory" validate -no-color
done

run_tests() {
  local directory="$1" log_file="$2"
  printf '\nTesting %s (mock AWS provider)\n' "$directory"
  if ! terraform -chdir="$directory" test -json -verbose > "$log_file"; then
    python3 - "$log_file" <<'PY'
import json, sys
for line in open(sys.argv[1]):
    record = json.loads(line)
    if record.get("type") in ("diagnostic", "test_summary", "test_run"):
        print(record.get("@message", ""))
        if record.get("diagnostic"):
            print(record["diagnostic"].get("detail", ""))
PY
    return 1
  fi
  python3 - "$log_file" <<'PY'
import json, sys
for line in open(sys.argv[1]):
    record = json.loads(line)
    if record.get("type") == "test_summary":
        print(record["@message"])
PY
}

run_tests . "$log_dir/root.jsonl"
run_tests modules/alb "$log_dir/alb.jsonl"
run_tests modules/ec2 "$log_dir/ec2.jsonl"
python3 modules/ec2/tests/assert_plan.py "$log_dir/ec2.jsonl"
python3 scripts/assert_resources.py "$log_dir/root.jsonl" "$log_dir/alb.jsonl"
