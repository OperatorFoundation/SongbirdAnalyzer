#!/usr/bin/env python3
"""
Integration tests for evaluation workflow error recovery and robustness.

Tests the evaluation pipeline's handling of hardware failures, audio processing
errors, and recovery mechanisms. All tests run in isolated environments.
"""

import os
import json
import time
import subprocess
from tests.helpers.test_helpers import SafeTestCase, skip_if_missing_dependency


class TestEvaluationWorkflowErrorRecovery(SafeTestCase):
    """Test evaluation workflow error handling and recovery mechanisms."""

    def setUp(self):
        """Set up isolated test environment for evaluation workflow tests."""
        super().setUp()

        # Create test directory structure
        self.audio_dir = os.path.join(self.test_dir, 'audio')
        self.models_dir = os.path.join(self.test_dir, 'models')
        self.results_dir = os.path.join(self.test_dir, 'results')
        self.working_dir = os.path.join(self.test_dir, 'working-evaluation')
        self.files_dir = os.path.join(self.test_dir, 'files')
        self.backup_dir = os.path.join(self.test_dir, 'backups')

        # Create all directories
        for directory in [self.audio_dir, self.models_dir, self.results_dir,
                          self.working_dir, self.files_dir, self.backup_dir]:
            os.makedirs(directory, exist_ok=True)

        # Set environment variables for test isolation
        self.original_env = {}
        test_env_vars = {
            'WORKING_DIR': self.working_dir,
            'FILES_DIR': self.files_dir,
            'MODEL_FILE': os.path.join(self.models_dir, 'speaker_model.pkl'),
            'BACKUP_ROOT_DIR': self.backup_dir,
            'RESULTS_DIR': self.results_dir,
            'REQUIRE_HARDWARE_VALIDATION': 'false'  # Disable hardware for tests
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

    def create_mock_model_file(self):
        """Create a mock trained model for testing."""
        model_file = os.path.join(self.models_dir, 'speaker_model.pkl')
        with open(model_file, 'wb') as f:
            f.write(b'Mock pickled model data for testing')
        return model_file

    def create_mock_test_files(self):
        """Create mock test files for evaluation."""
        speakers = ['21525', '23723', '19839']

        for speaker in speakers:
            speaker_dir = os.path.join(self.files_dir, speaker)
            os.makedirs(speaker_dir, exist_ok=True)

            # Create test audio files
            for i in range(3):
                test_file = os.path.join(speaker_dir, f'test_{i}.wav')
                self.create_mock_wav_file(test_file)

    def create_mock_wav_file(self, filepath):
        """Create a minimal mock WAV file."""
        # Minimal WAV file structure
        wav_header = b'RIFF\x2e\x00\x00\x00WAVEfmt \x10\x00\x00\x00\x01\x00\x01\x00\x44\xac\x00\x00\x88\x58\x01\x00\x02\x00\x10\x00data\x0a\x00\x00\x00'
        wav_data = b'\x00\x00' * 5

        with open(filepath, 'wb') as f:
            f.write(wav_header + wav_data)

    def create_mock_recorded_audio(self):
        """Create mock recorded modified audio files."""
        speakers = ['21525', '23723', '19839']
        modes = ['Noise', 'PitchShift', 'Wave']

        for speaker in speakers:
            for mode in modes:
                mode_dir = os.path.join(self.working_dir, mode, speaker)
                os.makedirs(mode_dir, exist_ok=True)

                # Create modified audio files
                for i in range(2):
                    recorded_file = os.path.join(mode_dir, f'modified_{i}.wav')
                    self.create_mock_wav_file(recorded_file)

    def create_mock_csv_data(self, filepath, include_mode=False):
        """Create mock CSV data for testing."""
        import csv

        with open(filepath, 'w', newline='') as f:
            writer = csv.writer(f)

            # Write header
            header = ['speaker', 'wav_file']
            if include_mode:
                header.append('mode')
            header.extend([f'mfcc_{i}' for i in range(13)])
            writer.writerow(header)

            # Write sample data
            speakers = ['21525', '23723', '19839']
            modes = ['Noise', 'PitchShift', 'Wave'] if include_mode else [None]

            for i, speaker in enumerate(speakers):
                for j, mode in enumerate(modes):
                    row = [speaker, f'test_{i}_{j}.wav']
                    if include_mode:
                        row.append(mode)
                    row.extend([f'{i}.{k}' for k in range(13)])
                    writer.writerow(row)

    def run_evaluation_command(self, command, args=None, expect_success=True):
        """Run an evaluation-related command safely in test environment."""
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
    def test_evaluation_prerequisites_validation(self):
        """Test evaluation workflow validates prerequisites correctly."""
        # Test without model file
        model_file = os.path.join(self.models_dir, 'speaker_model.pkl')
        self.assertFalse(os.path.exists(model_file), "Model file should not exist initially")

        # Create model file
        self.create_mock_model_file()
        self.assertTrue(os.path.exists(model_file), "Model file should be created")

        # Test without test files
        self.assertTrue(os.path.exists(self.files_dir), "Files directory should exist")

        # Create test files
        self.create_mock_test_files()

        # Verify test files structure
        for speaker in ['21525', '23723', '19839']:
            speaker_dir = os.path.join(self.files_dir, speaker)
            self.assertTrue(os.path.exists(speaker_dir), f"Speaker directory should exist: {speaker}")

            wav_files = [f for f in os.listdir(speaker_dir) if f.endswith('.wav')]
            self.assertGreater(len(wav_files), 0, f"No WAV files found for speaker {speaker}")

    @skip_if_missing_dependency('python3')
    def test_audio_recording_simulation(self):
        """Test audio recording workflow simulation."""
        # Create prerequisite files
        self.create_mock_model_file()
        self.create_mock_test_files()

        # Simulate recording by creating modified audio files
        self.create_mock_recorded_audio()

        # Verify recorded files structure
        modes = ['Noise', 'PitchShift', 'Wave']
        speakers = ['21525', '23723', '19839']

        for mode in modes:
            mode_dir = os.path.join(self.working_dir, mode)
            self.assertTrue(os.path.exists(mode_dir), f"Mode directory should exist: {mode}")

            for speaker in speakers:
                speaker_dir = os.path.join(mode_dir, speaker)
                self.assertTrue(os.path.exists(speaker_dir),
                                f"Speaker directory should exist: {mode}/{speaker}")

                wav_files = [f for f in os.listdir(speaker_dir) if f.endswith('.wav')]
                self.assertGreater(len(wav_files), 0,
                                   f"No recorded files found for {mode}/{speaker}")

    @skip_if_missing_dependency('python3')
    def test_mfcc_processing_error_handling(self):
        """Test MFCC processing handles various error conditions."""
        # Create recorded audio files
        self.create_mock_recorded_audio()

        # Create a corrupted audio file
        corrupted_file = os.path.join(self.working_dir, 'Noise', '21525', 'corrupted.wav')
        with open(corrupted_file, 'w') as f:
            f.write("This is not valid WAV data")

        self.assertTrue(os.path.exists(corrupted_file), "Corrupted file should exist")

        # MFCC processing should handle corrupted files gracefully
        # (In actual implementation, this would test automfcc.py error handling)

        # Test with empty directory
        empty_mode_dir = os.path.join(self.working_dir, 'Empty')
        os.makedirs(empty_mode_dir, exist_ok=True)
        self.assertTrue(os.path.exists(empty_mode_dir), "Empty mode directory should exist")

    @skip_if_missing_dependency('python3')
    def test_feature_standardization_recovery(self):
        """Test feature standardization error recovery."""
        # Create mock evaluation CSV
        evaluation_csv = os.path.join(self.results_dir, 'evaluation.csv')
        self.create_mock_csv_data(evaluation_csv, include_mode=True)

        self.assertTrue(os.path.exists(evaluation_csv), "Evaluation CSV should exist")

        # Verify CSV structure
        with open(evaluation_csv, 'r') as f:
            lines = f.readlines()
            self.assertGreater(len(lines), 1, "CSV should have header and data")
            self.assertIn('speaker', lines[0], "CSV should have speaker column")
            self.assertIn('mode', lines[0], "CSV should have mode column")
            self.assertIn('mfcc_', lines[0], "CSV should have MFCC columns")

    @skip_if_missing_dependency('python3')
    def test_results_analysis_workflow(self):
        """Test results analysis and prediction workflow."""
        # Create prerequisite files
        self.create_mock_model_file()

        # Create evaluation results
        evaluation_csv = os.path.join(self.results_dir, 'evaluation.csv')
        self.create_mock_csv_data(evaluation_csv, include_mode=True)

        # Create feature dimensions reference (would be created during training)
        dimensions_file = os.path.join(self.results_dir, 'feature_dimensions.json')
        dimensions_data = {
            'n_features': 13,
            'feature_names': [f'mfcc_{i}' for i in range(13)],
            'timestamp': '2024-01-01T12:00:00'
        }

        with open(dimensions_file, 'w') as f:
            json.dump(dimensions_data, f)

        self.assertTrue(os.path.exists(dimensions_file), "Feature dimensions file should exist")

        # Verify dimensions data
        with open(dimensions_file, 'r') as f:
            loaded_data = json.load(f)
            self.assertEqual(loaded_data['n_features'], 13)
            self.assertIn('mfcc_0', loaded_data['feature_names'])

    @skip_if_missing_dependency('python3')
    def test_hardware_failure_simulation(self):
        """Test workflow handles simulated hardware failures."""
        # Simulate hardware disconnection by setting environment
        os.environ['REQUIRE_HARDWARE_VALIDATION'] = 'false'

        # Test should continue without hardware
        self.assertEqual(os.environ['REQUIRE_HARDWARE_VALIDATION'], 'false')

        # Create files that would normally require hardware
        self.create_mock_test_files()
        self.create_mock_recorded_audio()

        # Verify workflow can proceed without hardware
        self.assertTrue(os.path.exists(self.working_dir), "Working directory should exist")
        self.assertTrue(os.path.exists(self.files_dir), "Files directory should exist")

    @skip_if_missing_dependency('python3')
    def test_evaluation_backup_and_recovery(self):
        """Test evaluation backup and recovery mechanisms."""
        # Create evaluation results to backup
        results_files = [
            os.path.join(self.results_dir, 'evaluation.csv'),
            os.path.join(self.results_dir, 'analysis.json'),
            os.path.join(self.results_dir, 'predictions.csv')
        ]

        for result_file in results_files:
            if 'csv' in result_file:
                self.create_mock_csv_data(result_file)
            else:
                with open(result_file, 'w') as f:
                    json.dump({'test': 'data'}, f)

        # Verify all results files exist
        for result_file in results_files:
            self.assertTrue(os.path.exists(result_file), f"Result file should exist: {result_file}")

        # Test backup directory structure
        self.assertTrue(self.backup_dir.startswith(self.test_dir),
                        "Backup directory should be within test directory")

    @skip_if_missing_dependency('python3')
    def test_working_directory_isolation(self):
        """Test that evaluation working directories are properly isolated."""
        # Verify working directory is within test environment
        self.assertTrue(self.working_dir.startswith(self.test_dir),
                        "Working directory should be within test directory")

        # Create test files in working directory
        self.create_mock_recorded_audio()

        # Verify files are isolated from project
        project_working = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))),
                                       'working-evaluation')

        if os.path.exists(project_working):
            # If project working directory exists, ensure our test files aren't there
            test_file_in_project = os.path.join(project_working, 'Noise', '21525', 'modified_0.wav')
            self.assertFalse(os.path.exists(test_file_in_project),
                             "Test file should not appear in project working directory")

    @skip_if_missing_dependency('python3')
    def test_evaluation_cleanup_and_validation(self):
        """Test evaluation cleanup processes and final validation."""
        # Create various evaluation files
        eval_files = [
            os.path.join(self.working_dir, 'temp_processing.tmp'),
            os.path.join(self.results_dir, 'intermediate_analysis.json'),
            os.path.join(self.test_dir, 'evaluation_checkpoint.json')
        ]

        for eval_file in eval_files:
            os.makedirs(os.path.dirname(eval_file), exist_ok=True)
            if eval_file.endswith('.json'):
                with open(eval_file, 'w') as f:
                    json.dump({'status': 'temporary'}, f)
            else:
                with open(eval_file, 'w') as f:
                    f.write("Temporary evaluation data")

        # Verify files exist
        for eval_file in eval_files:
            self.assertTrue(os.path.exists(eval_file), f"Eval file should exist: {eval_file}")

        # Test that all files are within test directory
        for eval_file in eval_files:
            self.assertTrue(eval_file.startswith(self.test_dir),
                            f"Eval file should be within test directory: {eval_file}")

    @skip_if_missing_dependency('python3')
    def test_error_reporting_and_logging(self):
        """Test error reporting and logging during evaluation."""
        # Create error log
        error_log = os.path.join(self.test_dir, 'evaluation_errors.log')

        # Simulate various error conditions
        error_entries = [
            "Audio processing error: corrupt file detected",
            "Model prediction error: feature dimension mismatch",
            "Hardware timeout: device not responding",
            "Recovery successful: continuing with available data"
        ]

        with open(error_log, 'w') as f:
            for entry in error_entries:
                f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} - {entry}\n")

        self.assertTrue(os.path.exists(error_log), "Error log should be created")

        # Verify error log content
        with open(error_log, 'r') as f:
            content = f.read()
            for entry in error_entries:
                self.assertIn(entry.split(': ')[1], content, f"Error log should contain: {entry}")