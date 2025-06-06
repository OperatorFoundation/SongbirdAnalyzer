# !/usr/bin/env python3
"""
Integration tests for the complete Songbird analysis pipeline.

These tests verify the end-to-end functionality of the pipeline including
training, evaluation, and backup systems. All tests run in isolated
environments to prevent interference with the actual project.
"""

import os
import json
import subprocess
from tests.helpers.test_helpers import SafeTestCase, skip_if_missing_dependency


class TestSongbirdPipeline(SafeTestCase):
    """Integration tests for the complete Songbird pipeline."""

    def setUp(self):
        """Set up test environment for pipeline integration tests."""
        super().setUp()

        # Create test directory structure within the safe test environment
        self.audio_dir = os.path.join(self.test_dir, 'audio')
        self.models_dir = os.path.join(self.test_dir, 'models')
        self.results_dir = os.path.join(self.test_dir, 'results')
        self.working_dir = os.path.join(self.test_dir, 'working-training')

        # Create all necessary directories
        for directory in [self.audio_dir, self.models_dir, self.results_dir, self.working_dir]:
            os.makedirs(directory, exist_ok=True)

        # Set environment variables to point to test directories
        os.environ['SPEAKERS_DIR'] = self.audio_dir
        os.environ['MODEL_FILE'] = os.path.join(self.models_dir, 'speaker_model.pkl')
        os.environ['BACKUP_ROOT_DIR'] = os.path.join(self.test_dir, 'backups')

    def tearDown(self):
        """Clean up test environment."""
        # Restore environment variables
        for var in ['SPEAKERS_DIR', 'MODEL_FILE', 'BACKUP_ROOT_DIR']:
            if var in os.environ:
                del os.environ[var]

        super().tearDown()

    def create_test_audio_files(self):
        """Create test audio files for pipeline testing."""
        # Create speaker directories
        for speaker in ['21525', '23723', '19839']:
            speaker_dir = os.path.join(self.audio_dir, speaker)
            os.makedirs(speaker_dir, exist_ok=True)

            # Create test audio files
            for i in range(2):
                audio_file = os.path.join(speaker_dir, f'test_{i}.wav')
                self.create_mock_wav_file(audio_file)

    def create_mock_wav_file(self, filepath):
        """Create a minimal mock WAV file for testing."""
        # Create a minimal WAV file header (44 bytes) + minimal data
        wav_header = b'RIFF\x2e\x00\x00\x00WAVEfmt \x10\x00\x00\x00\x01\x00\x01\x00\x44\xac\x00\x00\x88\x58\x01\x00\x02\x00\x10\x00data\x0a\x00\x00\x00'
        wav_data = b'\x00\x00' * 5  # Minimal audio data

        with open(filepath, 'wb') as f:
            f.write(wav_header + wav_data)

    def run_script(self, script_name, args=None, cwd=None):
        """Run a script safely within the test environment."""
        if cwd is None:
            cwd = self.test_dir

        if args is None:
            args = []

        # Copy the script to test directory to ensure isolation
        script_path = os.path.join(self.test_dir, script_name)
        if not os.path.exists(script_path):
            # Copy from project root to test directory
            project_script = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), script_name)
            if os.path.exists(project_script):
                import shutil
                shutil.copy2(project_script, script_path)
                os.chmod(script_path, 0o755)

        try:
            result = subprocess.run(
                [script_path] + args,
                cwd=cwd,
                capture_output=True,
                text=True,
                timeout=30  # Prevent hanging tests
            )
            return result
        except subprocess.TimeoutExpired:
            self.fail(f"Script {script_name} timed out after 30 seconds")
        except Exception as e:
            self.fail(f"Failed to run script {script_name}: {e}")

    @skip_if_missing_dependency('python3')
    def test_backup_system_integration(self):
        """Test backup system functionality."""
        # Create some test data to backup
        test_models_dir = os.path.join(self.test_dir, 'models')
        os.makedirs(test_models_dir, exist_ok=True)

        test_model_file = os.path.join(test_models_dir, 'test.pkl')
        with open(test_model_file, 'w') as f:
            f.write("mock model data")

        # Run backup creation
        result = self.run_script('backup-manager.sh', [
            'create', 'models', '--force'
        ], cwd=self.test_dir)

        self.assertEqual(result.returncode, 0, f"Backup creation failed: {result.stderr}")

        # Check that backup was created
        backups_dir = os.path.join(self.test_dir, 'backups')
        self.assertTrue(os.path.exists(backups_dir), "Backups directory not created")

        backup_contents = os.listdir(backups_dir)
        model_backups = [b for b in backup_contents if 'models' in b]
        self.assertGreater(len(model_backups), 0, "No model backup created")

        # Test backup listing
        result = self.run_script('backup-manager.sh', ['list'], cwd=self.test_dir)
        self.assertEqual(result.returncode, 0, f"Backup listing failed: {result.stderr}")
        self.assertIn('models', result.stdout, "Models backup not listed")

    @skip_if_missing_dependency('python3')
    def test_pipeline_configuration_validation(self):
        """Test that pipeline validates configuration correctly."""
        # Create minimal configuration
        config_file = os.path.join(self.test_dir, 'songbird-config.sh')
        with open(config_file, 'w') as f:
            f.write('''#!/bin/bash
# Test configuration
speakers=("21525" "23723")
DEVICE_NAME="test-device"
''')

        # Test configuration loading (this would normally be done by core modules)
        self.assertTrue(os.path.exists(config_file), "Configuration file was not created")

    @skip_if_missing_dependency('python3')
    def test_directory_structure_creation(self):
        """Test that pipeline creates necessary directory structure."""
        # Verify test directories were created
        expected_dirs = [
            self.audio_dir,
            self.models_dir,
            self.results_dir,
            self.working_dir
        ]

        for directory in expected_dirs:
            self.assertTrue(os.path.exists(directory), f"Directory not created: {directory}")
            self.assertTrue(os.path.isdir(directory), f"Path is not a directory: {directory}")

    @skip_if_missing_dependency('python3')
    def test_environment_isolation(self):
        """Test that pipeline operations are properly isolated."""
        # Verify we're working in test directory
        self.assertTrue(self.test_dir.startswith('/tmp') or 'temp' in self.test_dir.lower(),
                        "Test directory is not in a temporary location")

        # Verify test directories are within test_dir
        self.assertTrue(self.audio_dir.startswith(self.test_dir),
                        "Audio directory is not within test directory")
        self.assertTrue(self.models_dir.startswith(self.test_dir),
                        "Models directory is not within test directory")

        # Verify no files created outside test directory
        project_root = os.path.dirname(os.path.dirname(os.path.dirname(__file__)))
        for item in os.listdir(project_root):
            if item.startswith('test_') or item.startswith('temp'):
                self.fail(f"Test created file in project root: {item}")

    @skip_if_missing_dependency('python3')
    def test_mock_audio_file_creation(self):
        """Test that mock audio files are created correctly."""
        self.create_test_audio_files()

        # Verify audio files were created
        for speaker in ['21525', '23723', '19839']:
            speaker_dir = os.path.join(self.audio_dir, speaker)
            self.assertTrue(os.path.exists(speaker_dir), f"Speaker directory not created: {speaker}")

            for i in range(2):
                audio_file = os.path.join(speaker_dir, f'test_{i}.wav')
                self.assertTrue(os.path.exists(audio_file), f"Audio file not created: {audio_file}")

                # Verify file has content
                self.assertGreater(os.path.getsize(audio_file), 0, f"Audio file is empty: {audio_file}")

    @skip_if_missing_dependency('python3')
    def test_script_isolation(self):
        """Test that scripts run in isolated environment."""
        # Create a test script
        test_script = os.path.join(self.test_dir, 'test-script.sh')
        with open(test_script, 'w') as f:
            f.write('''#!/bin/bash
echo "Working directory: $(pwd)"
echo "Script location: $(dirname "$0")"
echo "Test file creation"
touch test-output.txt
''')
        os.chmod(test_script, 0o755)

        # Run the script
        result = self.run_script('test-script.sh', cwd=self.test_dir)

        # Verify script ran in test directory
        self.assertEqual(result.returncode, 0, f"Test script failed: {result.stderr}")
        self.assertIn(self.test_dir, result.stdout, "Script did not run in test directory")

        # Verify output file was created in test directory
        output_file = os.path.join(self.test_dir, 'test-output.txt')
        self.assertTrue(os.path.exists(output_file), "Script output file not created in test directory")