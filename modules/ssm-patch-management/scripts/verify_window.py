"""Check window ownership, enabled state and cutoff again after approval."""
import boto3
from datetime import datetime, timedelta, timezone


def check_window(events, context):
    ssm = boto3.client("ssm")
    execution = ssm.get_maintenance_window_execution(
        WindowExecutionId=events["window_execution_id"])
    window = ssm.get_maintenance_window(WindowId=events["window_id"])
    owned = False
    for page in ssm.get_paginator("describe_maintenance_window_executions").paginate(
            WindowId=events["window_id"]):
        if any(item["WindowExecutionId"] == events["window_execution_id"]
               for item in page["WindowExecutions"]):
            owned = True
            break
    latest_start = execution["StartTime"] + timedelta(
        hours=window["Duration"] - window["Cutoff"])
    if (not owned or not window["Enabled"] or execution["Status"] != "IN_PROGRESS"
            or datetime.now(timezone.utc) >= latest_start - timedelta(minutes=5)):
        raise RuntimeError("Production patch window is invalid, closed or near cutoff")
    return {"allowed": True}
