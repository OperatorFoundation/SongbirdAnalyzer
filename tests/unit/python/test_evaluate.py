"""Simple, focused tests for evaluate.py functionality."""
import unittest
import os
import pandas as pd
import sys

# Add project root to path for imports
sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__)))))

from tests.helpers.test_helpers import SafeTestCase
import evaluate


class TestEvaluateCoreFunctions(SafeTestCase):
    """Test the core extracted functions from evaluate.py."""

    def test_load_evaluation_data(self):
        """Test loading evaluation data from CSV."""
        # Create test CSV file
        csv_content = """speaker,wav_file,mfcc_1,mfcc_2
21525,test1.wav,1.0,2.0
23723,test2.wav,3.0,4.0
21525,test3.wav,5.0,6.0"""

        csv_file = self.create_test_file('test_data.csv', csv_content)

        # Test loading
        data = evaluate.load_evaluation_data(csv_file)

        self.assertIsInstance(data, pd.DataFrame)
        self.assertEqual(len(data), 3)
        self.assertIn('speaker', data.columns)
        self.assertIn('wav_file', data.columns)
        self.assertIn('mfcc_1', data.columns)

    def test_load_evaluation_data_missing_file(self):
        """Test loading data from non-existent file."""
        with self.assertRaises(FileNotFoundError):
            evaluate.load_evaluation_data('nonexistent.csv')

    def test_load_evaluation_data_missing_speaker_column(self):
        """Test loading data without required speaker column."""
        csv_content = """wav_file,mfcc_1,mfcc_2
test1.wav,1.0,2.0
test2.wav,3.0,4.0"""

        csv_file = self.create_test_file('bad_data.csv', csv_content)

        with self.assertRaises(ValueError) as context:
            evaluate.load_evaluation_data(csv_file)

        self.assertIn('speaker', str(context.exception))

    def test_extract_features_and_labels(self):
        """Test extracting features and labels from data."""
        # Create test DataFrame
        data = pd.DataFrame({
            'speaker': ['21525', '23723', '21525'],
            'wav_file': ['test1.wav', 'test2.wav', 'test3.wav'],
            'mfcc_1': [1.0, 2.0, 3.0],
            'mfcc_2': [4.0, 5.0, 6.0]
        })

        mfccs, labels, metadata = evaluate.extract_features_and_labels(data)

        # Verify features
        self.assertIsInstance(mfccs, pd.DataFrame)
        self.assertIn('mfcc_1', mfccs.columns)
        self.assertIn('mfcc_2', mfccs.columns)
        self.assertNotIn('speaker', mfccs.columns)
        self.assertNotIn('wav_file', mfccs.columns)

        # Verify labels
        self.assertIsInstance(labels, pd.Series)
        self.assertEqual(len(labels), 3)
        self.assertEqual(labels.iloc[0], '21525')

        # Verify metadata
        self.assertIn('total_samples', metadata)
        self.assertIn('feature_columns', metadata)
        self.assertIn('has_wav_file', metadata)
        self.assertEqual(metadata['total_samples'], 3)
        self.assertTrue(metadata['has_wav_file'])

    def test_extract_features_and_labels_no_wav_file(self):
        """Test extracting features without wav_file column."""
        data = pd.DataFrame({
            'speaker': ['21525', '23723'],
            'mfcc_1': [1.0, 2.0],
            'mfcc_2': [3.0, 4.0]
        })

        mfccs, labels, metadata = evaluate.extract_features_and_labels(data)

        self.assertNotIn('wav_file', mfccs.columns)
        self.assertFalse(metadata['has_wav_file'])
        self.assertEqual(len(metadata['excluded_columns']), 1)

    def test_calculate_data_statistics(self):
        """Test calculating data statistics."""
        # Create test DataFrame with mode information
        data = pd.DataFrame({
            'speaker': ['21525', '23723', '21525', '23723'],
            'wav_file': ['test-n.wav', 'test-p.wav', 'test-w.wav', 'test-n.wav'],
            'mfcc_1': [1.0, 2.0, 3.0, 4.0]
        })

        stats = evaluate.calculate_data_statistics(data)

        # Verify basic statistics
        self.assertEqual(stats['total_samples'], 4)
        self.assertEqual(stats['unique_speakers'], 2)
        self.assertTrue(stats['has_modes'])
        self.assertEqual(stats['unique_modes'], 3)  # n, p, w

        # Verify speaker counts
        self.assertIn('21525', stats['speaker_counts'])
        self.assertIn('23723', stats['speaker_counts'])
        self.assertEqual(stats['speaker_counts']['21525'], 2)
        self.assertEqual(stats['speaker_counts']['23723'], 2)

        # Verify mode counts
        self.assertIn('n', stats['mode_counts'])
        self.assertIn('p', stats['mode_counts'])
        self.assertIn('w', stats['mode_counts'])
        self.assertEqual(stats['mode_counts']['n'], 2)

    def test_calculate_data_statistics_no_modes(self):
        """Test calculating statistics without mode information."""
        data = pd.DataFrame({
            'speaker': ['21525', '23723', '21525'],
            'mfcc_1': [1.0, 2.0, 3.0]
        })

        stats = evaluate.calculate_data_statistics(data)

        self.assertFalse(stats['has_modes'])
        self.assertEqual(stats['unique_modes'], 0)
        self.assertEqual(len(stats['mode_counts']), 0)

    def test_save_evaluation_data(self):
        """Test saving evaluation data to files."""
        # Create test data
        mfccs = pd.DataFrame({
            'mfcc_1': [1.0, 2.0],
            'mfcc_2': [3.0, 4.0]
        })
        labels = pd.Series(['21525', '23723'])
        output_prefix = 'test_output'

        files_created = evaluate.save_evaluation_data(mfccs, labels, output_prefix)

        # Verify files were created
        self.assertEqual(len(files_created), 2)

        expected_files = ['test_output_mfccs.csv', 'test_output_speakers.csv']
        for expected_file in expected_files:
            self.assertIn(expected_file, files_created)
            self.assertFileExists(expected_file)

        # Verify file contents
        saved_mfccs = pd.read_csv('test_output_mfccs.csv')
        saved_labels = pd.read_csv('test_output_speakers.csv')

        self.assertEqual(len(saved_mfccs), 2)
        self.assertEqual(len(saved_labels), 2)
        self.assertIn('mfcc_1', saved_mfccs.columns)

    def test_print_data_statistics(self):
        """Test printing data statistics (capture output)."""
        import io
        from contextlib import redirect_stdout

        stats = {
            'total_samples': 4,
            'speaker_counts': {'21525': 2, '23723': 2},
            'has_modes': True,
            'mode_counts': {'n': 2, 'p': 1, 'w': 1}
        }

        # Capture printed output
        captured_output = io.StringIO()
        with redirect_stdout(captured_output):
            evaluate.print_data_statistics(stats)

        output = captured_output.getvalue()

        # Verify key information is printed
        self.assertIn('Total samples: 4', output)
        self.assertIn('Speaker 21525: 2', output)
        self.assertIn('Speaker 23723: 2', output)
        self.assertIn('Mode n: 2', output)


class TestEvaluateMainFunction(SafeTestCase):
    """Test the main evaluation function."""

    def test_evaluate_data_pipeline(self):
        """Test complete evaluation pipeline."""
        # Create test CSV file
        csv_content = """speaker,wav_file,mfcc_1,mfcc_2,mfcc_3
21525,test-n.wav,1.0,2.0,3.0
23723,test-p.wav,4.0,5.0,6.0
21525,test-w.wav,7.0,8.0,9.0
23723,test-n.wav,10.0,11.0,12.0"""

        csv_file = self.create_test_file('evaluation_data.csv', csv_content)
        output_prefix = 'eval_output'

        results = evaluate.evaluate_data_pipeline(csv_file, output_prefix)

        # Verify results structure
        self.assertIn('stats', results)
        self.assertIn('metadata', results)
        self.assertIn('files_created', results)
        self.assertIn('mfccs_shape', results)
        self.assertIn('labels_count', results)

        # Verify statistics
        stats = results['stats']
        self.assertEqual(stats['total_samples'], 4)
        self.assertEqual(stats['unique_speakers'], 2)
        self.assertTrue(stats['has_modes'])

        # Verify files were created
        self.assertEqual(len(results['files_created']), 2)
        for file_path in results['files_created']:
            self.assertFileExists(file_path)

        # Verify data shapes
        self.assertEqual(results['mfccs_shape'], (4, 3))  # 4 samples, 3 MFCC features
        self.assertEqual(results['labels_count'], 4)

    def test_evaluate_data_pipeline_default_prefix(self):
        """Test pipeline with default output prefix."""
        csv_content = """speaker,mfcc_1,mfcc_2
21525,1.0,2.0
23723,3.0,4.0"""

        csv_file = self.create_test_file('test_data.csv', csv_content)

        results = evaluate.evaluate_data_pipeline(csv_file)

        # Should use filename without .csv as prefix (basename only)
        expected_prefix = os.path.join(self.test_dir, 'test_data')
        self.assertEqual(results['output_prefix'], expected_prefix)

        # Files should be created with default prefix
        expected_files = ['test_data_mfccs.csv', 'test_data_speakers.csv']
        for expected_file in expected_files:
            self.assertFileExists(expected_file)

    def test_evaluate_data_pipeline_no_wav_file(self):
        """Test pipeline without wav_file column."""
        csv_content = """speaker,mfcc_1,mfcc_2
21525,1.0,2.0
23723,3.0,4.0"""

        csv_file = self.create_test_file('simple_data.csv', csv_content)

        results = evaluate.evaluate_data_pipeline(csv_file, 'simple_output')

        # Should handle missing wav_file gracefully
        self.assertFalse(results['metadata']['has_wav_file'])
        self.assertFalse(results['stats']['has_modes'])
        self.assertEqual(results['stats']['unique_modes'], 0)


class TestEvaluateErrorHandling(SafeTestCase):
    """Test error handling in evaluate functions."""

    def test_pipeline_with_invalid_file(self):
        """Test pipeline with non-existent file."""
        with self.assertRaises(FileNotFoundError):
            evaluate.evaluate_data_pipeline('nonexistent.csv')

    def test_pipeline_with_invalid_data(self):
        """Test pipeline with invalid data structure."""
        # Create CSV without speaker column
        csv_content = """wav_file,mfcc_1,mfcc_2
test1.wav,1.0,2.0
test2.wav,3.0,4.0"""

        csv_file = self.create_test_file('invalid_data.csv', csv_content)

        with self.assertRaises(ValueError):
            evaluate.evaluate_data_pipeline(csv_file)


class TestEvaluateCLI(SafeTestCase):
    """Test command-line interface."""

    def test_cli_insufficient_args(self):
        """Test CLI with insufficient arguments."""
        import subprocess

        result = subprocess.run([
            'python3', f'{self.project_root}/evaluate.py'
        ], capture_output=True, text=True, cwd=self.test_dir)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Usage:', result.stdout + result.stderr)

    def test_cli_valid_args(self):
        """Test CLI with valid arguments."""
        import subprocess

        # Create test data
        csv_content = """speaker,mfcc_1,mfcc_2
21525,1.0,2.0
23723,3.0,4.0"""

        csv_file = self.create_test_file('cli_test.csv', csv_content)

        result = subprocess.run([
            'python3', f'{self.project_root}/evaluate.py',
            csv_file, 'cli_output'
        ], capture_output=True, text=True, cwd=self.test_dir)

        # Should run successfully
        self.assertEqual(result.returncode, 0)

        # Should create expected output files
        expected_files = ['cli_output_mfccs.csv', 'cli_output_speakers.csv']
        for expected_file in expected_files:
            self.assertFileExists(expected_file)

    def test_cli_default_output_prefix(self):
        """Test CLI with default output prefix."""
        import subprocess

        csv_content = """speaker,mfcc_1
21525,1.0"""

        csv_file = self.create_test_file('default_test.csv', csv_content)

        result = subprocess.run([
            'python3', f'{self.project_root}/evaluate.py',
            csv_file
        ], capture_output=True, text=True, cwd=self.test_dir)

        self.assertEqual(result.returncode, 0)

        # Should create files with default prefix
        self.assertFileExists('default_test_mfccs.csv')
        self.assertFileExists('default_test_speakers.csv')


if __name__ == '__main__':
    unittest.main()