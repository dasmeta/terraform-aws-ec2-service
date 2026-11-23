"""Exercise the actual Python handlers embedded in the Automation documents."""
import importlib.util
import json
import sys
import types
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[2]
# No credentials or boto3 installation are needed for local/CI tests.
sys.modules.setdefault('boto3', types.ModuleType('boto3'))


def load(module, filename):
    path = ROOT / 'modules' / module / 'scripts' / filename
    spec = importlib.util.spec_from_file_location(path.stem, path)
    handler = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(handler)
    return handler


class CandidateTests(unittest.TestCase):
    def setUp(self):
        self.handler = load('eks-ami-promotion', 'verify_candidate.py')
        self.events = dict(parameter_name='/example/recommended', release_version='1.34.1-20261101',
                           image_id='ami-0123456789abcdef0', cluster_name='example', node_group_name='workers')
        self.ssm, self.ec2, self.eks = Mock(), Mock(), Mock()
        self.ssm.get_parameter.return_value = {'Parameter': {'Value': json.dumps({
            'image_id': self.events['image_id'], 'release_version': self.events['release_version']})}}
        self.ec2.describe_images.return_value = {'Images': [{'State': 'available'}]}
        self.eks.describe_nodegroup.return_value = {'nodegroup': {
            'status': 'ACTIVE', 'amiType': 'AL2023_x86_64_STANDARD', 'version': '1.34', 'health': {'issues': []}}}
        self.client = patch.object(self.handler.boto3, 'client', create=True,
                                  side_effect=lambda name: {'ssm': self.ssm, 'ec2': self.ec2, 'eks': self.eks}[name])
        self.client.start(); self.addCleanup(self.client.stop)

    def test_validated_candidate_is_accepted(self):
        self.handler.verify_candidate(self.events, None)
        self.ec2.describe_images.assert_called_once_with(ImageIds=[self.events['image_id']], Owners=['amazon'])

    def test_image_change_with_same_release_is_rejected(self):
        self.ssm.get_parameter.return_value['Parameter']['Value'] = json.dumps({
            'image_id': 'ami-0123456789abcdef1', 'release_version': self.events['release_version']})
        with self.assertRaises(RuntimeError): self.handler.verify_candidate(self.events, None)
        self.eks.describe_nodegroup.assert_not_called()

    def test_custom_launch_template_image_is_rejected(self):
        self.eks.describe_nodegroup.return_value['nodegroup']['launchTemplate'] = {'id': 'lt-example', 'version': '1'}
        self.ec2.describe_launch_template_versions.return_value = {
            'LaunchTemplateVersions': [{'LaunchTemplateData': {'ImageId': 'ami-custom'}}]}
        with self.assertRaises(RuntimeError): self.handler.verify_candidate(self.events, None)

    def test_parameter_drift_aborts_before_eks_access(self):
        for field in ('image_id', 'release_version'):
            with self.subTest(field=field):
                original = self.events[field]; self.events[field] = 'changed'
                with self.assertRaises(RuntimeError): self.handler.verify_candidate(self.events, None)
                self.events[field] = original
        self.eks.describe_nodegroup.assert_not_called()

    def test_unavailable_image_rejected(self):
        self.ec2.describe_images.return_value = {'Images': []}
        with self.assertRaises(RuntimeError): self.handler.verify_candidate(self.events, None)

    def test_unhealthy_or_custom_nodegroups_rejected(self):
        group = self.eks.describe_nodegroup.return_value['nodegroup']
        for key, value in [('status', 'DEGRADED'), ('amiType', 'CUSTOM'), ('version', '1.33'), ('health', {'issues': [{'code': 'failure'}]})]:
            with self.subTest(key=key):
                original = group[key]; group[key] = value
                with self.assertRaises(RuntimeError): self.handler.verify_candidate(self.events, None)
                group[key] = original


class ComplianceTests(unittest.TestCase):
    def setUp(self):
        self.handler = load('ssm-patch-management', 'verify_compliance.py')
        self.ssm = Mock()
        self.state = {'InstanceId': 'i-0123456789abcdef0', 'Operation': 'Scan',
                      'OperationStartTime': datetime.now(timezone.utc), 'OperationEndTime': datetime.now(timezone.utc), 'MissingCount': 0, 'FailedCount': 0,
                      'InstalledPendingRebootCount': 0, 'InstalledRejectedCount': 0}
        self.ssm.describe_instance_patch_states.return_value = {'InstancePatchStates': [self.state]}
        self.state['OperationStartTime'] = self.state['OperationEndTime']
        self.started_at = datetime.now(timezone.utc) - timedelta(minutes=1)
        ticks = iter(range(0, 100000, 100))
        for name, kwargs in [('sleep', {'return_value': None}), ('monotonic', {'side_effect': lambda: next(ticks)})]:
            clock_patch = patch.object(self.handler.time, name, **kwargs)
            clock_patch.start(); self.addCleanup(clock_patch.stop)

        p = patch.object(self.handler.boto3, 'client', create=True, return_value=self.ssm)
        p.start(); self.addCleanup(p.stop)

    def check(self): return self.handler.verify_compliance({'instance_id': self.state['InstanceId'], 'scan_started_at': self.started_at.isoformat()}, None)

    def test_clean_scan_passes(self): self.assertEqual(self.check()['compliance'], 'COMPLIANT')

    def test_missing_failed_pending_reboot_and_rejected_patches_fail(self):
        for key in ('MissingCount', 'FailedCount', 'InstalledPendingRebootCount', 'InstalledRejectedCount'):
            with self.subTest(key=key):
                self.state[key] = 1
                with self.assertRaises(RuntimeError): self.check()
                self.state[key] = 0

    def test_delayed_scan_data_is_retried(self):
        previous = dict(self.state, Operation='Install')
        self.ssm.describe_instance_patch_states.side_effect = [
            {'InstancePatchStates': [previous]}, {'InstancePatchStates': [self.state]}]
        self.assertEqual(self.check()['compliance'], 'COMPLIANT')
        self.handler.time.sleep.assert_called_once_with(10)

    def test_stale_scan_rejected(self):
        self.state['OperationEndTime'] -= timedelta(hours=1)
        self.state['OperationStartTime'] -= timedelta(hours=1)
        with self.assertRaises(RuntimeError): self.check()

    def test_missing_data_rejected(self):
        self.ssm.describe_instance_patch_states.return_value = {'InstancePatchStates': []}
        with self.assertRaises(RuntimeError): self.check()

    def test_install_record_cannot_replace_post_install_scan(self):
        self.state['Operation'] = 'Install'
        with self.assertRaises(RuntimeError): self.check()


class WindowTests(unittest.TestCase):
    def setUp(self):
        self.handler = load('ssm-patch-management', 'verify_window.py')
        self.ssm = Mock()
        self.execution = {'Status': 'IN_PROGRESS', 'StartTime': datetime.now(timezone.utc)}
        self.window = {'Enabled': True, 'Duration': 3, 'Cutoff': 1}
        self.ssm.get_maintenance_window_execution.return_value = self.execution
        self.ssm.get_maintenance_window.return_value = self.window
        self.ssm.get_paginator.return_value.paginate.return_value = [{'WindowExecutions': [{'WindowExecutionId': 'execution'}]}]
        p = patch.object(self.handler.boto3, 'client', create=True, return_value=self.ssm)
        p.start(); self.addCleanup(p.stop)

    def check(self): return self.handler.check_window({'window_id': 'window', 'window_execution_id': 'execution'}, None)

    def test_open_window_accepted(self): self.assertTrue(self.check()['allowed'])

    def test_closed_or_near_cutoff_rejected(self):
        self.execution['StartTime'] -= timedelta(hours=2)
        with self.assertRaises(RuntimeError): self.check()

    def test_disabled_or_finished_window_rejected(self):
        self.window['Enabled'] = False
        with self.assertRaises(RuntimeError): self.check()
        self.window['Enabled'] = True; self.execution['Status'] = 'SUCCESS'
        with self.assertRaises(RuntimeError): self.check()

    def test_execution_from_another_window_rejected(self):
        self.ssm.get_paginator.return_value.paginate.return_value = [{'WindowExecutions': []}]
        with self.assertRaises(RuntimeError): self.check()


if __name__ == '__main__': unittest.main()
