"""Fail closed if the validated AWS AMI or managed node group changed."""
import json
import boto3


def verify_candidate(events, context):
    record = json.loads(boto3.client("ssm").get_parameter(
        Name=events["parameter_name"])["Parameter"]["Value"])
    if (record.get("release_version"), record.get("image_id")) != (
            events["release_version"], events["image_id"]):
        raise RuntimeError("Candidate release or AMI identity changed after validation")
    images = boto3.client("ec2").describe_images(
        ImageIds=[events["image_id"]], Owners=["amazon"])["Images"]
    if len(images) != 1 or images[0]["State"] != "available":
        raise RuntimeError("Candidate must be an available AWS-owned AMI")
    group = boto3.client("eks").describe_nodegroup(
        clusterName=events["cluster_name"],
        nodegroupName=events["node_group_name"])["nodegroup"]
    if group["status"] != "ACTIVE" or group.get("health", {}).get("issues"):
        raise RuntimeError("Node group must be ACTIVE without health issues")
    if group["amiType"] == "CUSTOM":
        raise RuntimeError("Custom AMIs require a separate launch-template workflow")
    if not events["release_version"].startswith(group["version"] + "."):
        raise RuntimeError("Candidate must match the node group's Kubernetes version")
    if group.get("launchTemplate"):
        template = group["launchTemplate"]
        versions = boto3.client("ec2").describe_launch_template_versions(
            LaunchTemplateId=template["id"], Versions=[template["version"]])
        if versions["LaunchTemplateVersions"][0]["LaunchTemplateData"].get("ImageId"):
            raise RuntimeError("Launch template specifies a custom AMI")
    return {"release_version": record["release_version"], "image_id": record["image_id"]}
