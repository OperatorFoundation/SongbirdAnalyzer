"""
Python test helper utilities for safe test execution.
Provides base classes and utilities for Python unit tests.
"""

import os
import tempfile
import shutil
import unittest
import sys


class SafeTestCase(unittest.TestCase):
    """Base test case that ensures safe file operations."""

    def setUp(self):
        """Set up safe test environment with isolated directory."""
        # Create isolated test directory
        self.test_dir = tempfile.mkdtemp()
        self.original_cwd = os.getcwd()

        # Change to test directory to prevent accidental writes to project root
        os.chdir(self.test_dir)

        # Store project root for imports
        self.project_root = os.path.dirname(os.path.dirname(os.path.dirname(__file__)))

        # Ensure project root is in Python path
        if self.project_root not in sys.path:
            sys.path.insert(0, self.project_root)

    def tearDown(self):
        """Clean up test environment."""
        # Return to original directory
        os.chdir(self.original_cwd)

        # Clean up test directory
        if os.path.exists(self.test_dir):
            shutil.rmtree(self.test_dir)

    def create_test_file(self, filename, content=""):
        """Create a file safely in the test directory."""
        filepath = os.path.join(self.test_dir, filename)

        # Ensure directory exists
        os.makedirs(os.path.dirname(filepath), exist_ok=True)

        with open(filepath, 'w') as f:
            f.write(content)

        return filepath

    def create_test_directory(self, dirname):
        """Create a directory safely in the test directory."""
        dirpath = os.path.join(self.test_dir, dirname)
        os.makedirs(dirpath, exist_ok=True)
        return dirpath

    def create_mock_audio_structure(self, speakers=['21525', '23723'], modes=['n', 'p', 'w']):
        """Create mock audio directory structure for testing."""
        for speaker in speakers:
            speaker_dir = self.create_test_directory(speaker)

            for mode in modes:
                for i in range(2):
                    filename = f"test_{mode}_{i:03d}.wav"
                    filepath = os.path.join(speaker, filename)
                    self.create_test_file(filepath, f"mock audio {mode} {i}")

        return self.test_dir

    def create_mock_csv_data(self, filename="test.csv", num_rows=10):
        """Create mock CSV file with MFCC-like data."""
        import csv
        import random

        filepath = self.create_test_file(filename)

        with open(filepath, 'w', newline='') as csvfile:
            writer = csv.writer(csvfile)

            # Header
            header = ['speaker', 'wav_file'] + [f'mfcc_{i}' for i in range(13)]
            writer.writerow(header)

            # Data rows
            for i in range(num_rows):
                speaker = random.choice(['21525', '23723', '19839'])
                wav_file = f'test_{i:03d}.wav'
                mfcc_values = [random.uniform(-1, 1) for _ in range(13)]
                writer.writerow([speaker, wav_file] + mfcc_values)

        return filepath

    def assertFileExists(self, filepath, msg=None):
        """Assert that a file exists."""
        if not os.path.isfile(filepath):
            raise AssertionError(msg or f"File does not exist: {filepath}")

    def assertDirectoryExists(self, dirpath, msg=None):
        """Assert that a directory exists."""
        if not os.path.isdir(dirpath):
            raise AssertionError(msg or f"Directory does not exist: {dirpath}")

    def assertFileContains(self, filepath, text, msg=None):
        """Assert that a file contains specific text."""
        self.assertFileExists(filepath)

        with open(filepath, 'r') as f:
            content = f.read()

        if text not in content:
            raise AssertionError(msg or f"File {filepath} does not contain: {text}")


class MockAudioTestCase(SafeTestCase):
    """Test case with additional audio file mocking utilities."""

    def create_mock_wav_file(self, filename, duration_seconds=1, sample_rate=44100):
        """Create a mock WAV file with basic header structure."""
        import struct

        filepath = self.create_test_file(filename)

        # Calculate data size
        num_samples = int(duration_seconds * sample_rate)
        data_size = num_samples * 2  # 16-bit samples
        file_size = 36 + data_size

        with open(filepath, 'wb') as f:
            # WAV header
            f.write(b'RIFF')
            f.write(struct.pack('<I', file_size))
            f.write(b'WAVE')

            # Format chunk
            f.write(b'fmt ')
            f.write(struct.pack('<I', 16))  # Chunk size
            f.write(struct.pack('<H', 1))  # Audio format (PCM)
            f.write(struct.pack('<H', 1))  # Number of channels
            f.write(struct.pack('<I', sample_rate))  # Sample rate
            f.write(struct.pack('<I', sample_rate * 2))  # Byte rate
            f.write(struct.pack('<H', 2))  # Block align
            f.write(struct.pack('<H', 16))  # Bits per sample

            # Data chunk
            f.write(b'data')
            f.write(struct.pack('<I', data_size))

            # Write silence (zeros)
            f.write(b'\x00' * data_size)

        return filepath


def skip_if_missing_dependency(module_name):
    """Decorator to skip tests if a dependency is missing."""

    def decorator(test_func):
        try:
            __import__(module_name)
            return test_func
        except ImportError:
            return unittest.skip(f"Skipping test: {module_name} not available")(test_func)

    return decorator


def requires_external_tool(tool_name):
    """Decorator to skip tests if an external tool is not available."""

    def decorator(test_func):
        import shutil
        if shutil.which(tool_name):
            return test_func
        else:
            return unittest.skip(f"Skipping test: {tool_name} not available")(test_func)

    return decorator