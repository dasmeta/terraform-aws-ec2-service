"""Report API behavior without credentials or live resources."""
import importlib.util
import unittest
from pathlib import Path
from unittest.mock import Mock

spec = importlib.util.spec_from_file_location('patching_report', Path(__file__).resolve().parents[2] / 'scripts' / 'patching_report.py')
reporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reporter)


class ReportTests(unittest.TestCase):
    def test_scoped_paginated_results_and_pending_approvals(self):
        session = Mock(region_name='example-region')
        api = session.client.return_value
        api.describe_instance_patch_states.return_value = {'InstancePatchStates': []}
        command_pages = [
            {'CommandInvocations': [{'DocumentName': 'AWS-RunPatchBaseline', 'Status': 'Success'}]},
            {'CommandInvocations': [{'DocumentName': 'AWS-RunPatchBaseline', 'Status': 'Failed'},
                                    {'DocumentName': 'AWS-RunShellScript', 'Status': 'Success'}]},
        ]
        automation_pages = [{'AutomationExecutionMetadataList': [
            {'DocumentName': 'patch', 'AutomationExecutionId': 'one'},
            {'DocumentName': 'patch-other', 'AutomationExecutionId': 'excluded'},
        ]}, {'AutomationExecutionMetadataList': [
            {'DocumentName': 'patch', 'AutomationExecutionId': 'two'},
        ]}]
        commands, automations = Mock(), Mock()
        commands.paginate.return_value = command_pages
        automations.paginate.return_value = automation_pages
        api.get_paginator.side_effect = lambda name: {'list_command_invocations': commands,
                                                      'describe_automation_executions': automations}[name]
        api.get_automation_execution.side_effect = lambda AutomationExecutionId: {
            'AutomationExecution': {'AutomationExecutionStatus': {'one': 'Waiting', 'two': 'TimedOut'}[AutomationExecutionId]}}
        result = reporter.collect(session, ['i-0123456789abcdef0'], ['patch'], 24)
        self.assertFalse(result['instances'][0]['compliance_data_available'])
        self.assertEqual(len(result['instances'][0]['patch_invocations']), 2)
        self.assertEqual(result['execution_record_counts'], {'successful': 1, 'pending': 1, 'failed_or_interrupted': 2})
        self.assertEqual(api.get_automation_execution.call_count, 2)
        self.assertEqual(commands.paginate.call_args.kwargs['InstanceId'], 'i-0123456789abcdef0')


if __name__ == '__main__':
    unittest.main()
