"""Wait for this execution's post-install scan; fail on stale or noncompliant data."""
import time
from datetime import datetime
import boto3


def verify_compliance(events, context):
    ssm = boto3.client('ssm')
    scan_started_at = datetime.fromisoformat(events['scan_started_at'])
    deadline = time.monotonic() + 480
    while time.monotonic() < deadline:
        states = ssm.describe_instance_patch_states(
            InstanceIds=[events['instance_id']])['InstancePatchStates']
        if len(states) == 1:
            state = states[0]
            if (state['InstanceId'] == events['instance_id']
                    and state.get('Operation') == 'Scan'
                    and state['OperationStartTime'] >= scan_started_at):
                counts = ('MissingCount', 'FailedCount', 'InstalledPendingRebootCount',
                          'InstalledRejectedCount', 'CriticalNonCompliantCount',
                          'SecurityNonCompliantCount', 'OtherNonCompliantCount')
                if any(state.get(key, 0) != 0 for key in counts):
                    raise RuntimeError('Post-install patch scan is noncompliant: ' + str(state))
                return {'instance_id': state['InstanceId'], 'compliance': 'COMPLIANT'}
        # Run Command completion can precede the asynchronous compliance update.
        time.sleep(10)
    raise RuntimeError('Fresh post-install scan compliance did not arrive within 480 seconds')
