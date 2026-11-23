#!/usr/bin/env python3
"""Read scoped patch results and compliance; retain JSON as private change evidence.

Requires boto3. Counts are execution records, not unique changes: parent
Automations and child commands are reported separately.
"""
import argparse
import json
from datetime import datetime, timedelta, timezone


def collect(session, instance_ids, documents, hours=168):
    ssm = session.client('ssm')
    since = datetime.now(timezone.utc) - timedelta(hours=hours)
    report = {'collected_at': datetime.now(timezone.utc).isoformat(),
              'since': since.isoformat(), 'region': session.region_name,
              'instances': [], 'automations': []}
    for instance_id in instance_ids:
        states = ssm.describe_instance_patch_states(InstanceIds=[instance_id])['InstancePatchStates']
        commands = []
        for page in ssm.get_paginator('list_command_invocations').paginate(
                InstanceId=instance_id, Details=True,
                Filters=[{'key': 'InvokedAfter', 'value': since.isoformat()}]):
            commands.extend(item for item in page['CommandInvocations']
                            if item.get('DocumentName') == 'AWS-RunPatchBaseline')
        report['instances'].append({'instance_id': instance_id, 'patch_states': states,
                                    'compliance_data_available': bool(states),
                                    'patch_invocations': commands})
    for document in documents:
        for page in ssm.get_paginator('describe_automation_executions').paginate(Filters=[
                {'Key': 'DocumentNamePrefix', 'Values': [document]},
                {'Key': 'StartTimeAfter', 'Values': [since.isoformat()]}]):
            for item in page['AutomationExecutionMetadataList']:
                if item['DocumentName'] == document:
                    report['automations'].append(ssm.get_automation_execution(
                        AutomationExecutionId=item['AutomationExecutionId'])['AutomationExecution'])
    statuses = [a['AutomationExecutionStatus'] for a in report['automations']]
    statuses += [c['Status'] for i in report['instances'] for c in i['patch_invocations']]
    pending = {'Pending', 'InProgress', 'Waiting', 'PendingApproval', 'Scheduled',
               'Delayed', 'RunbookInProgress'}
    report['execution_record_counts'] = {
        'successful': sum(s == 'Success' for s in statuses),
        'pending': sum(s in pending for s in statuses),
        'failed_or_interrupted': sum(s not in pending | {'Success'} for s in statuses),
    }
    return report


def main():
    import boto3
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', required=True)
    parser.add_argument('--region', required=True)
    parser.add_argument('--instance-id', action='append', default=[])
    parser.add_argument('--document-name', action='append', default=[])
    parser.add_argument('--hours', type=int, default=168)
    args = parser.parse_args()
    if not (args.instance_id or args.document_name):
        parser.error('Provide at least one --instance-id or --document-name')
    if args.hours <= 0:
        parser.error('--hours must be positive')
    session = boto3.Session(profile_name=args.profile, region_name=args.region)
    print(json.dumps(collect(session, args.instance_id, args.document_name, args.hours),
                     default=str, indent=2))


if __name__ == '__main__':
    main()
