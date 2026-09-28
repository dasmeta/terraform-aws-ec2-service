#!/usr/bin/env python3
"""Check real nested resources from `terraform test -json -verbose` output."""
import json
import sys
from pathlib import Path


def resources(module):
    result = list(module.get("resources", []))
    for child in module.get("child_modules", []):
        result.extend(resources(child))
    return result


states, summary = {}, None
with Path(sys.argv[1]).open() as log:
    for line in log:
        record = json.loads(line)
        if record["type"] == "test_summary":
            summary = record["test_summary"]
        elif record["type"] == "test_state":
            states[record["@testrun"]] = resources(record["test_state"]["root_module"])
assert summary is not None, "Missing Terraform test summary"
assert summary["status"] == "pass" and summary["skipped"] == 0, summary


def of_type(run, resource_type):
    return [item["values"] for item in states[run] if item["type"] == resource_type]


for run in ("secure_defaults", "custom_options", "existing_security_groups"):
    instances = of_type(run, "aws_instance")
    assert len(instances) == 1, f"{run}: expected exactly one instance"
    instance = instances[0]
    metadata = instance["metadata_options"][0]
    assert metadata["http_tokens"] == "required", f"{run}: IMDSv2 is mandatory"
    assert metadata["http_endpoint"] == "enabled" and metadata["http_put_response_hop_limit"] == 1
    assert instance["root_block_device"][0]["encrypted"] is True
    assert instance["ami"] == "ami-0123456789abcdef0"
    assert instance["subnet_id"] == "subnet-0123456789abcdef0"
    assert instance["tags"]["Environment"] == "test" and instance["tags"]["Name"] == "test-service"
    assert instance["volume_tags"]["Environment"] == "test"

instance = of_type("secure_defaults", "aws_instance")[0]
assert instance["instance_type"] == "t3.micro"
assert instance["associate_public_ip_address"] is False
assert instance["monitoring"] is True
assert instance["vpc_security_group_ids"] == ["sg-0123456789abcdef0"]
assert not of_type("secure_defaults", "aws_vpc_security_group_ingress_rule")
sg = of_type("secure_defaults", "aws_security_group")
assert len(sg) == 1 and sg[0]["vpc_id"] == "vpc-0123456789abcdef0"
egress = of_type("secure_defaults", "aws_vpc_security_group_egress_rule")
assert len(egress) == 1 and egress[0]["ip_protocol"] == "-1" and egress[0]["cidr_ipv4"] == "0.0.0.0/0"

instance = of_type("custom_options", "aws_instance")[0]
assert instance["instance_type"] == "t3.small"
assert instance["associate_public_ip_address"] is True and instance["monitoring"] is False
assert instance["key_name"] == "operator-key" and instance["iam_instance_profile"] == "service-profile"
assert instance["user_data"] == "#!/bin/sh\necho ready"
assert set(instance["vpc_security_group_ids"]) == {"sg-0123456789abcdef0", "sg-09999999999999999"}
ingress = of_type("custom_options", "aws_vpc_security_group_ingress_rule")
assert len(ingress) == 2
assert all(rule["ip_protocol"] == "tcp" and rule["from_port"] == rule["to_port"] for rule in ingress)
assert any(rule["from_port"] == 8080 and rule["cidr_ipv4"] == "10.0.0.0/8" and rule["description"] == "Private web" for rule in ingress)
assert any(rule["from_port"] == 8081 and rule["referenced_security_group_id"] == "sg-08888888888888888" for rule in ingress)
assert all(rule["security_group_id"] == "sg-0123456789abcdef0" for rule in ingress)
assert all(rule["tags"]["Environment"] == "test" for rule in ingress)

assert not of_type("existing_security_groups", "aws_security_group")
assert not of_type("existing_security_groups", "aws_vpc_security_group_ingress_rule")
assert not of_type("existing_security_groups", "aws_vpc_security_group_egress_rule")
assert of_type("existing_security_groups", "aws_instance")[0]["vpc_security_group_ids"] == ["sg-09999999999999999"]
print("Nested EC2 instance, metadata, volume, tags, and security group checks passed.")
