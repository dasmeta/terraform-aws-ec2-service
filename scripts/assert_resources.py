#!/usr/bin/env python3
"""Verify nested upstream resources, not only wrapper outputs, from mock test logs."""
import json
import sys
from pathlib import Path


def resources(module):
    result = list(module.get("resources", []))
    for child in module.get("child_modules", []):
        result.extend(resources(child))
    return result


def read_log(path):
    states, plans, summary = {}, {}, None
    with Path(path).open() as log:
        for line in log:
            record = json.loads(line)
            if record["type"] == "test_summary":
                summary = record["test_summary"]
            elif record["type"] == "test_state":
                states[record["@testrun"]] = resources(record["test_state"]["root_module"])
            elif record["type"] == "test_plan":
                plans[record["@testrun"]] = record["test_plan"].get("resource_changes", [])
    assert summary is not None, "Missing Terraform test summary"
    assert summary["status"] == "pass" and summary["skipped"] == 0, summary
    return states, plans


def of_type(items, resource_type):
    return [r for r in items if r["type"] == resource_type and r.get("mode") == "managed"]


root_states, root_plans = read_log(sys.argv[1])
alb_states, alb_plans = read_log(sys.argv[2])

assert not [r for r in root_plans["disabled"] if r.get("mode") == "managed"]
ec2_only = root_plans["ec2_only"]
assert len(of_type(ec2_only, "aws_instance")) == 1
assert of_type(ec2_only, "aws_instance")[0]["change"]["after"]["tags"]["Name"] == "example-compute"
assert not of_type(ec2_only, "aws_lb")
assert not of_type(ec2_only, "aws_lb_target_group")
alb_only = root_plans["alb_only_existing"]
assert not of_type(alb_only, "aws_instance")
assert len(of_type(alb_only, "aws_lb")) == 1
assert of_type(alb_only, "aws_lb")[0]["change"]["after"]["name"] == "example-service"
assert len(of_type(alb_only, "aws_lb_target_group_attachment")) == 1

unknown_plan = root_plans["combined_unknown_id_plan"]
attachments = of_type(unknown_plan, "aws_lb_target_group_attachment")
assert len(attachments) == 3
new_attachments = [r for r in attachments if "__created_instance" in r["address"]]
assert len(new_attachments) == 2
assert all(r["change"]["after_unknown"].get("target_id") is True for r in new_attachments)
assert all(r["change"]["after"]["port"] == 8080 for r in new_attachments)
assert all(r["change"]["actions"] == ["create"] for r in new_attachments)

combined = root_states["combined_id_wiring"]
instance = of_type(combined, "aws_instance")[0]["values"]
assert instance["tags"]["Name"] == "example-compute"
assert of_type(combined, "aws_lb")[0]["values"]["name"] == "example-service"
assert of_type(combined, "aws_lb_target_group")[0]["values"]["name"] == "example-service"
assert of_type(root_plans["custom_target_group_name"], "aws_lb_target_group")[0]["change"]["after"]["name"] == "custom-service-web"
attachments = [r["values"] for r in of_type(combined, "aws_lb_target_group_attachment")]
assert {a["target_id"] for a in attachments} == {instance["id"], "i-0123456789abcdef1"}
assert all(a["port"] == 8080 for a in attachments)
assert len(of_type(combined, "aws_instance")) == 1
assert len(of_type(combined, "aws_lb")) == 1
assert all(r["values"]["target_type"] == "instance" for r in of_type(combined, "aws_lb_target_group"))
connection_rules = [r["values"] for r in of_type(combined, "aws_vpc_security_group_ingress_rule")]
assert len(connection_rules) == 1
assert connection_rules[0]["referenced_security_group_id"] is not None
assert connection_rules[0]["cidr_ipv4"] is None
assert connection_rules[0]["from_port"] == connection_rules[0]["to_port"] == 8080

initial = alb_states["existing_targets_and_empty_group"]
after_removal = alb_states["remove_registration"]
for state in (initial, after_removal):
    assert not of_type(state, "aws_instance"), "ALB must never own existing EC2 instances"
    assert len(of_type(state, "aws_lb_target_group")) == 2
before_targets = {r["address"]: r["values"] for r in of_type(initial, "aws_lb_target_group_attachment")}
after_targets = {r["address"]: r["values"] for r in of_type(after_removal, "aws_lb_target_group_attachment")}
assert len(before_targets) == 2 and len(after_targets) == 1
remaining = next(iter(after_targets))
assert after_targets[remaining]["id"] == before_targets[remaining]["id"]
assert after_targets[remaining]["target_id"] == "i-0123456789abcdef0"
assert after_targets[remaining]["port"] == 8080
assert sorted(t["port"] for t in before_targets.values()) == [8080, 8081]
assert all(r["values"]["health_check"][0]["enabled"] for r in of_type(initial, "aws_lb_target_group"))
alb = of_type(initial, "aws_lb")[0]["values"]
assert alb["internal"] is True and alb["enable_deletion_protection"] is True
assert alb["load_balancer_type"] == "application"
ingress = of_type(initial, "aws_vpc_security_group_ingress_rule")
assert len(ingress) == 1 and ingress[0]["values"]["cidr_ipv4"] == "10.0.0.0/8"
assert ingress[0]["values"]["from_port"] == 80

backend = root_states["existing_backend_opt_in"]
assert not of_type(backend, "aws_instance")
groups = of_type(backend, "aws_security_group")
assert len(groups) == 1, "The existing backend SG must not become module-owned"
assert groups[0]["values"]["name_prefix"] == "example-service-alb-"
assert groups[0]["values"]["description"] == "Public application entry point"
egress = of_type(backend, "aws_vpc_security_group_egress_rule")
assert len(egress) == 1
rule = egress[0]["values"]
assert rule["from_port"] == rule["to_port"] == 8000 and rule["ip_protocol"] == "tcp"
assert rule["referenced_security_group_id"] == "sg-0123456789abcdef0" and rule["cidr_ipv4"] is None
ingress = of_type(backend, "aws_vpc_security_group_ingress_rule")
assert len(ingress) == 1
rule = ingress[0]["values"]
assert rule["security_group_id"] == "sg-0123456789abcdef0"
assert rule["referenced_security_group_id"] == groups[0]["values"]["id"]
assert rule["from_port"] == rule["to_port"] == 8000 and rule["cidr_ipv4"] is None
alb = of_type(backend, "aws_lb")[0]["values"]
assert alb["internal"] is False and alb["enable_deletion_protection"] is False
assert alb["idle_timeout"] == 300

print("Nested ALB resources, lifecycle isolation, restricted backend access, unknown-ID planning and root wiring checks passed.")

sensitive_plan = root_plans["sensitive_bootstrap"]
sensitive_instance = of_type(sensitive_plan, "aws_instance")[0]["change"]
assert sensitive_instance["after_sensitive"].get("user_data") is True
assert len(of_type(sensitive_plan, "aws_lb_target_group_attachment")) == 1

for run_name in ("source_identity_unchanged", "source_identity_reordered"):
    rules = of_type(root_plans[run_name], "aws_vpc_security_group_ingress_rule")
    assert len(rules) == 4
    assert all(r["change"]["actions"] == ["no-op"] for r in rules), run_name
inserted_rules = of_type(root_plans["source_identity_inserted"], "aws_vpc_security_group_ingress_rule")
assert len(inserted_rules) == 6
assert sum(r["change"]["actions"] == ["no-op"] for r in inserted_rules) == 4
assert sum(r["change"]["actions"] == ["create"] for r in inserted_rules) == 2
print("Sensitive bootstrap and stable ALB source identity regressions passed.")

computed = root_plans["computed_network_external_groups"]
assert not of_type(computed, "aws_security_group")
computed_rules = of_type(computed, "aws_vpc_security_group_ingress_rule")
assert {r["address"] for r in computed_rules} == {
    "aws_vpc_security_group_ingress_rule.client[0]",
    "aws_vpc_security_group_ingress_rule.backend[0]",
}
client = next(r for r in computed_rules if ".client[" in r["address"])
backend = next(r for r in computed_rules if ".backend[" in r["address"])
assert client["change"]["after_unknown"]["cidr_ipv4"] is True
assert backend["change"]["after_unknown"]["from_port"] is True
assert backend["change"]["after_unknown"]["to_port"] is True
computed_attachment, = of_type(computed, "aws_lb_target_group_attachment")
assert computed_attachment["change"]["after_unknown"]["port"] is True
print("Computed CIDR/port planning with externally managed security groups passed.")
