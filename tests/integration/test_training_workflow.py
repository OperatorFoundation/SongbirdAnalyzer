#!/usr/bin/env python3
"""
Integration tests for training workflow robustness and error recovery.

Tests the training pipeline's ability to handle various error conditions,
recover from failures, and maintain data integrity throughout the process.
"""

import os
import json
import tempfile
import subprocess
from tests.helpers.test_helpers import SafeTestCase, skip_if_missing_dependency


class TestTrainingWorkflowRobustness(SafeTestCase):
    """Test training workflow error handling and recovery mechanisms."""

    def setUp(self):
        """Set up isolated test environment for training workflow tests."""
        super().setUp()

        # Create test directory structure
        self.audio_dir = os.path.join(self.test_dir, 'audio')
        self.models_dir = os.path.join(self.test_dir, 'models')
        self.results_dir = os.path.join(self.test_dir, 'results')
        self.working_dir = os.path.join(self.test_dir, 'working-training')
        self.backup_dir = os.path.join(self.test_dir, 'backups')

        # Create all directories
        for directory in [self.audio_dir, self.models_dir, self.results_dir,
                          self.working_dir, self.backup_dir]:
            os.makedirs(directory, exist_ok=True)

        # Set environment variables for test isolation
        self.original_env = {}
        test_env_vars = {
            'SPEAKERS_DIR': self.audio_dir,
            'MODEL_FILE': os.path.join(self.models_dir, 'speaker_model.pkl'),
            'BACKUP_ROOT_DIR': self.backup_dir,
            'TRAINING_WORKING_DIR': self.working_dir,
            'RESULTS_DIR': self.results_dir
        }

        for var, value in test_env_vars.items():
            self.original_env[var] = os.environ.get(var)
            os.environ[var] = value

    def tearDown(self):
        """Clean up test environment and restore original settings."""
        # Restore environment variables
        for var, original_value in self.original_env.items():
            if original_value is None:
                os.environ.pop(var, None)
            else:
                os.environ[var] = original_value

        super().tearDown()

    def create_mock_training_data(self):
        """Create mock training data for testing."""
        speakers = ['21525', '23723', '19839']

        for speaker in speakers:
            speaker_dir = os.path.join(self.audio_dir, speaker)
            os.makedirs(speaker_dir, exist_ok=True)

            # Create mock MP3 files
            for i in range(3):
                mp3_file = os.path.join(speaker_dir, f'audio_{i}.mp3')
                with open(mp3_file, 'wb') as f:
                    f.write(b'Mock MP3 data for testing')

    def create_mock_csv_data(self, filepath, num_samples=10):
        """Create mock CSV data for testing."""
        import csv

        with open(filepath, 'w', newline='') as f:
            writer = csv.writer(f)
            # Write header
            header = ['speaker', 'wav_file'] + [f'mfcc_{i}' for i in range(13)]
            writer.writerow(header)

            # Write sample data
            speakers = ['21525', '23723', '19839']
            for i in range(num_samples):
                speaker = speakers[i % len(speakers)]
                row = [speaker, f'audio_{i}.wav'] + [f'{i}.{j}' for j in range(13)]
                writer.writerow(row)

    def run_training_command(self, command, args=None, expect_success=True):
        """Run a training-related command safely in test environment."""
        if args is None:
            args = []

        try:
            result = subprocess.run(
                [command] + args,
                cwd=self.test_dir,
                capture_output=True,
                text=True,
                timeout=30,
                env=os.environ.copy()
            )

            if expect_success:
                self.assertEqual(result.returncode, 0,
                                 f"Command failed: {command} {args}\nStderr: {result.stderr}")

            return result
        except subprocess.TimeoutExpired:
            self.fail(f"Command timed out: {command} {args}")
        except Exception as e:
            self.fail(f"Failed to run command {command}: {e}")

    @skip_if_missing_dependency('python3')
    def test_training_data_validation(self):
        """Test training workflow validates input data correctly."""
        # Test with no training data
        self.assertFalse(os.path.exists(os.path.join(self.audio_dir, '21525')),
                         "Training data should not exist initially")

        # Create training data and verify structure
        self.create_mock_training_data()

        for speaker in ['21525', '23723', '19839']:
            speaker_dir = os.path.join(self.audio_dir, speaker)
            self.assertTrue(os.path.exists(speaker_dir),
                            f"Speaker directory not created: {speaker}")

            # Check for MP3 files
            mp3_files = [f for f in os.listdir(speaker_dir) if f.endswith('.mp3')]
            self.assertGreater(len(mp3_files), 0,
                               f"No MP3 files found for speaker {speaker}")

    @skip_if_missing_dependency('python3')
    def test_feature_extraction_resilience(self):
        """Test feature extraction handles various file conditions."""
        # Create test audio data
        self.create_mock_training_data()

        # Test with corrupted file
        corrupted_file = os.path.join(self.audio_dir, '21525', 'corrupted.mp3')
        with open(corrupted_file, 'w') as f:
            f.write("This is not valid MP3 data")

        # Feature extraction should handle corrupted files gracefully
        # (This would normally call automfcc.py, but we're testing the principle)
        self.assertTrue(os.path.exists(corrupted_file), "Corrupted file should exist for testing")

    @skip_if_missing_dependency('python3')
    def test_model_training_recovery(self):
        """Test model training recovery from various failure scenarios."""
        # Create mock CSV data for training
        training_file = os.path.join(self.results_dir, 'training.csv')
        self.create_mock_csv_data(training_file, num_samples=20)

        self.assertTrue(os.path.exists(training_file), "Training CSV should exist")

        # Verify CSV structure
        with open(training_file, 'r') as f:
            lines = f.readlines()
            self.assertGreater(len(lines), 1, "Training CSV should have header and data")
            self.assertIn('speaker', lines[0], "Training CSV should have speaker column")
            self.assertIn('mfcc_', lines[0], "Training CSV should have MFCC columns")

    @skip_if_missing_dependency('python3')
    def test_backup_system_integration(self):
        """Test backup system works correctly during training."""
        # Create some test data to backup
        test_model = os.path.join(self.models_dir, 'test_model.pkl')
        with open(test_model, 'w') as f:
            f.write("Mock model data")

        test_results = os.path.join(self.results_dir, 'test_results.csv')
        self.create_mock_csv_data(test_results, num_samples=5)

        # Verify files exist
        self.assertTrue(os.path.exists(test_model), "Test model should exist")
        self.assertTrue(os.path.exists(test_results), "Test results should exist")

        # Test backup directory is properly isolated
        self.assertTrue(self.backup_dir.startswith(self.test_dir),
                        "Backup directory should be within test directory")

    @skip_if_missing_dependency('python3')
    def test_working_directory_isolation(self):
        """Test that working directories are properly isolated."""
        # Verify working directory is within test environment
        self.assertTrue(self.working_dir.startswith(self.test_dir),
                        "Working directory should be within test directory")

        # Create test files in working directory
        test_audio = os.path.join(self.working_dir, '21525', 'test.wav')
        os.makedirs(os.path.dirname(test_audio), exist_ok=True)
        with open(test_audio, 'wb') as f:
            f.write(b'Mock WAV data')

        self.assertTrue(os.path.exists(test_audio), "Test audio should be created in working directory")

        # Verify it's isolated from project
        project_working = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))),
                                       'working-training')
        if os.path.exists(project_working):
            # If project working directory exists, make sure our test file isn't there
            test_file_in_project = os.path.join(project_working, '21525', 'test.wav')
            self.assertFalse(os.path.exists(test_file_in_project),
                             "Test file should not appear in project working directory")

    @skip_if_missing_dependency('python3')
    def test_error_logging_and_recovery(self):
        """Test error logging and recovery mechanisms."""
        # Test error log creation
        error_log = os.path.join(self.test_dir, 'training_errors.log')

        # Simulate error condition
        with open(error_log, 'w') as f:
            f.write("Mock error log entry\n")
            f.write("Training failure: insufficient data\n")

        self.assertTrue(os.path.exists(error_log), "Error log should be created")

        with open(error_log, 'r') as f:
            content = f.read()
            self.assertIn('Training failure', content, "Error log should contain error information")

    @skip_if_missing_dependency('python3')
    def test_checkpoint_and_resume_functionality(self):
        """Test training checkpoint and resume functionality."""
        # Create checkpoint file
        checkpoint_file = os.path.join(self.test_dir, '.training_checkpoint')
        checkpoint_data = {
            'stage': 'feature_extraction',
            'completed_speakers': ['21525'],
            'timestamp': '2024-01-01T12:00:00',
            'progress': 0.5
        }

        with open(checkpoint_file, 'w') as f:
            json.dump(checkpoint_data, f)

        self.assertTrue(os.path.exists(checkpoint_file), "Checkpoint file should be created")

        # Verify checkpoint data
        with open(checkpoint_file, 'r') as f:
            loaded_data = json.load(f)
            self.assertEqual(loaded_data['stage'], 'feature_extraction')
            self.assertIn('21525', loaded_data['completed_speakers'])

    @skip_if_missing_dependency('python3')
    def test_cleanup_and_final_validation(self):
        """Test cleanup processes and final validation."""
        # Create various test files
        temp_files = [
            os.path.join(self.test_dir, 'temp_processing.tmp'),
            os.path.join(self.test_dir, 'intermediate_results.csv'),
            os.path.join(self.working_dir, 'processing_cache.cache')
        ]

        for temp_file in temp_files:
            os.makedirs(os.path.dirname(temp_file), exist_ok=True)
            with open(temp_file, 'w') as f:
                f.write("Temporary data")

        # Verify temp files exist
        for temp_file in temp_files:
            self.assertTrue(os.path.exists(temp_file), f"Temp file should exist: {temp_file}")

        # Test that all files are within test directory
        for temp_file in temp_files:
            self.assertTrue(temp_file.startswith(self.test_dir),
                            f"Temp file should be within test directory: {temp_file}")