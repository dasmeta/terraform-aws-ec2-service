# Verification

Run terraform init -backend=false, terraform validate and terraform test from each changed module, then python3 -m unittest discover -s tests/patching -v. See docs/patching-readiness.md for AWS acceptance and recovery gates.
