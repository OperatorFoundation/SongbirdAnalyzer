"""Tests for automfcc functionality."""
import unittest
import os
import csv
import tempfile
import sys
from unittest.mock import patch, MagicMock
import numpy as np

# Add project root to path for imports
sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__)))))

from tests.helpers.test_helpers import SafeTestCase, skip_if_missing_dependency
import automfcc


class TestAutomfccCoreFunctions(SafeTestCase):
    """Test the core extracted functions from automfcc."""

    @skip_if_missing_dependency('librosa')
    def test_extract_features(self):
        """Test the extract_features function."""
        # Create mock signal data
        signal = np.random.random(1000)
        sample_rate = 22050

        with patch('librosa.feature.mfcc') as mock_mfcc, \
                patch('librosa.feature.delta') as mock_delta:
            # Mock librosa returns
            mock_mfcc.return_value = np.random.random((13, 50))
            mock_delta.return_value = np.random.random((13, 50))

            features = automfcc.extract_features(signal, sample_rate)

            # Verify structure
            self.assertIsInstance(features, dict)
            expected_keys = ['mfccs', 'mfccs_seq', 'delta_mfccs', 'delta_mfccs_seq',
                             'delta2_mfccs', 'delta2_mfccs_seq']
            for key in expected_keys:
                self.assertIn(key, features)

    def test_generate_csv_header(self):
        """Test CSV header generation."""
        # Create mock features
        features = {
            'mfccs': [1.0, 2.0, 3.0],
            'delta_mfccs': [1.1, 2.1, 3.1],
            'delta2_mfccs': [1.2, 2.2, 3.2]
        }

        # Test with mode
        header_with_mode = automfcc.generate_csv_header(features, include_mode=True)
        self.assertIn('speaker', header_with_mode)
        self.assertIn('wav_file', header_with_mode)
        self.assertIn('mode', header_with_mode)

        # Test without mode
        header_no_mode = automfcc.generate_csv_header(features, include_mode=False)
        self.assertIn('speaker', header_no_mode)
        self.assertIn('wav_file', header_no_mode)
        self.assertNotIn('mode', header_no_mode)

    def test_detect_directory_structure(self):
        """Test directory structure detection."""
        # Test speaker-based structure (no modes)
        speaker_root = self.create_test_directory('speakers')
        speaker1 = self.create_test_directory('speakers/speaker1')
        self.create_test_file('speakers/speaker1/audio1.wav', 'mock audio')

        has_modes, dirs = automfcc.detect_directory_structure(speaker_root)
        self.assertFalse(has_modes)
        self.assertIn('speaker1', dirs)

        # Test mode-based structure
        mode_root = self.create_test_directory('modes')
        mode1 = self.create_test_directory('modes/mode1')
        mode1_speaker = self.create_test_directory('modes/mode1/speaker1')
        self.create_test_file('modes/mode1/speaker1/audio1.wav', 'mock audio')

        has_modes, dirs = automfcc.detect_directory_structure(mode_root)
        self.assertTrue(has_modes)
        self.assertIn('mode1', dirs)

    def test_extract_speaker_labels(self):
        """Test speaker label extraction."""
        # Create test CSV with speaker data
        csv_content = 'speaker,wav_file,mfcc_1\nspeaker1,file1.wav,1.0\nspeaker2,file2.wav,2.0'
        input_csv = self.create_test_file('input.csv', csv_content)
        output_csv = os.path.join(self.test_dir, 'output_speakers.csv')

        automfcc.extract_speaker_labels(input_csv, output_csv)

        # Verify output file exists and has correct content
        self.assertFileExists(output_csv)
        with open(output_csv, 'r') as f:
            content = f.read()
            self.assertIn('speaker1', content)
            self.assertIn('speaker2', content)

    def test_combine_mode_files(self):
        """Test combining mode files."""
        # Create mock mode files
        mode1_content = 'speaker,wav_file,mode,mfcc_1\nspeaker1,file1.wav,mode1,1.0'
        mode2_content = 'speaker,wav_file,mode,mfcc_1\nspeaker1,file2.wav,mode2,2.0'

        mode1_file = self.create_test_file('base_mode1_mfccs.csv', mode1_content)
        mode2_file = self.create_test_file('base_mode2_mfccs.csv', mode2_content)

        output_file = os.path.join(self.test_dir, 'combined.csv')

        total_rows, unique_speakers = automfcc.combine_mode_files(
            output_file, 'base', ['mode1', 'mode2']
        )

        # Verify results
        self.assertEqual(total_rows, 2)
        self.assertEqual(unique_speakers, 1)
        self.assertFileExists(output_file)


class TestAutomfccMainFunction(SafeTestCase):
    """Test the main extraction function."""

    @patch('automfcc.librosa')
    @patch('automfcc.plt')
    def test_extract_mfcc_features_speaker_structure(self, mock_plt, mock_librosa):
        """Test main extraction function with speaker structure."""
        # Mock librosa operations
        mock_librosa.load.return_value = (np.random.random(1000), 22050)
        mock_librosa.feature.mfcc.return_value = np.random.random((13, 50))
        mock_librosa.feature.delta.return_value = np.random.random((13, 50))

        # Create speaker-based directory structure
        working_dir = self.create_test_directory('working')
        speaker_dir = self.create_test_directory('working/speaker1')
        self.create_test_file('working/speaker1/audio1.wav', 'mock audio')
        self.create_test_file('working/speaker1/audio2.wav', 'mock audio')

        output_csv = os.path.join(self.test_dir, 'output.csv')

        # Configure to disable spinner for testing
        config = {
            'enable_spinner': False,
            'enable_visualization': False
        }

        result = automfcc.extract_mfcc_features(working_dir, output_csv, config)

        # Verify results
        self.assertIsInstance(result, dict)
        self.assertIn('structure_type', result)
        self.assertIn('total_time', result)
        self.assertFalse(result['has_modes'])

        # Verify output files
        self.assertFileExists(output_csv)
        self.assertFileExists(output_csv.replace('.csv', '_speakers.csv'))

    @patch('automfcc.librosa')
    @patch('automfcc.plt')
    def test_extract_mfcc_features_mode_structure(self, mock_plt, mock_librosa):
        """Test main extraction function with mode structure."""
        # Mock librosa operations
        mock_librosa.load.return_value = (np.random.random(1000), 22050)
        mock_librosa.feature.mfcc.return_value = np.random.random((13, 50))
        mock_librosa.feature.delta.return_value = np.random.random((13, 50))

        # Create mode-based directory structure
        working_dir = self.create_test_directory('working')
        mode_dir = self.create_test_directory('working/mode1')
        speaker_dir = self.create_test_directory('working/mode1/speaker1')
        self.create_test_file('working/mode1/speaker1/audio1.wav', 'mock audio')

        output_csv = os.path.join(self.test_dir, 'output.csv')

        # Configure to disable spinner for testing
        config = {
            'enable_spinner': False,
            'enable_visualization': False
        }

        result = automfcc.extract_mfcc_features(working_dir, output_csv, config)

        # Verify results
        self.assertIsInstance(result, dict)
        self.assertTrue(result['has_modes'])

        # Verify output files
        self.assertFileExists(output_csv)


class TestAutomfccErrorHandling(SafeTestCase):
    """Test error handling in automfcc."""

    def test_invalid_directory(self):
        """Test behavior with invalid directory."""
        with self.assertRaises(ValueError):
            automfcc.extract_mfcc_features('nonexistent_dir', 'output.csv')

    def test_empty_directory(self):
        """Test behavior with empty directory."""
        empty_dir = self.create_test_directory('empty')

        with self.assertRaises(SystemExit):
            automfcc.extract_mfcc_features(empty_dir, 'output.csv')


class TestAutomfccCLI(SafeTestCase):
    """Test command-line interface."""

    def test_cli_insufficient_args(self):
        """Test CLI with insufficient arguments."""
        import subprocess

        result = subprocess.run([
            'python3', f'{self.project_root}/automfcc.py'
        ], capture_output=True, text=True, cwd=self.test_dir)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Usage:', result.stdout + result.stderr)

    def test_cli_valid_args(self):
        """Test CLI with valid arguments (directory structure test)."""
        import subprocess

        # Create minimal test directory structure to avoid actual processing
        test_dir = self.create_test_directory('test_working')
        speaker_dir = self.create_test_directory('test_working/speaker1')
        # Create a non-WAV file to trigger early exit without full processing
        self.create_test_file('test_working/speaker1/readme.txt', 'test')

        result = subprocess.run([
            'python3', f'{self.project_root}/automfcc.py',
            test_dir, 'output.csv'
        ], capture_output=True, text=True, cwd=self.test_dir)

        # Should exit gracefully (not crash) even with no WAV files
        # The important thing is that it didn't crash with argument parsing
        output = result.stdout + result.stderr
        self.assertNotIn('Usage:', output)  # No usage error means args were parsed


if __name__ == '__main__':
    unittest.main()