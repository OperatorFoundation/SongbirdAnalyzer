"""Simple, focused tests for train.py functionality."""
import unittest
import os
import pandas as pd
import tempfile
import sys
from unittest.mock import patch, MagicMock
import numpy as np

# Add project root to path for imports
sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__)))))

from tests.helpers.test_helpers import SafeTestCase, skip_if_missing_dependency
import train


class TestTrainCoreFunctions(SafeTestCase):
    """Test the core extracted functions from train.py."""

    def test_split_data(self):
        """Test the split_data function."""
        # Create test DataFrame
        df = pd.DataFrame({
            'speaker': ['21525', '23723', '21525'],
            'mfcc_1': [1.0, 2.0, 3.0],
            'mfcc_2': [4.0, 5.0, 6.0]
        })

        features, target = train.split_data(df, 'speaker')

        # Verify split
        self.assertIn('mfcc_1', features.columns)
        self.assertIn('mfcc_2', features.columns)
        self.assertNotIn('speaker', features.columns)
        self.assertIn('speaker', target.columns)
        self.assertEqual(len(features), 3)
        self.assertEqual(len(target), 3)

    def test_split_data_missing_column(self):
        """Test split_data with missing column."""
        df = pd.DataFrame({'mfcc_1': [1.0, 2.0], 'mfcc_2': [3.0, 4.0]})

        with self.assertRaises(ValueError):
            train.split_data(df, 'nonexistent_column')

    def test_prepare_data_for_training(self):
        """Test data preparation function."""
        # Create test DataFrame with wav_file column
        df = pd.DataFrame({
            'speaker': ['21525', '23723', '21525'],
            'wav_file': ['file1.wav', 'file2.wav', 'file3.wav'],
            'mfcc_1': [1.0, 2.0, 3.0],
            'mfcc_2': [4.0, 5.0, 6.0]
        })

        features, target, wav_files = train.prepare_data_for_training(df)

        # Verify results
        self.assertIsInstance(features, pd.DataFrame)
        self.assertIsInstance(wav_files, pd.Series)
        self.assertEqual(len(wav_files), 3)
        self.assertIn('mfcc_1', features.columns)
        self.assertNotIn('wav_file', features.columns)

    def test_prepare_data_missing_wav_file(self):
        """Test data preparation without wav_file column."""
        df = pd.DataFrame({
            'speaker': ['21525', '23723'],
            'mfcc_1': [1.0, 2.0]
        })

        with self.assertRaises(ValueError) as context:
            train.prepare_data_for_training(df)

        self.assertIn('wav_file', str(context.exception))

    def test_split_train_test_data(self):
        """Test train/test splitting function."""
        # Create test data
        features = pd.DataFrame({
            'mfcc_1': [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0],
            'mfcc_2': [2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0]
        })
        target = pd.Series(['A', 'B', 'A', 'B', 'A', 'B', 'A', 'B', 'A', 'B'])
        wav_files = pd.Series([f'file{i}.wav' for i in range(10)])

        config = {'test_size': 0.2, 'random_state': 42}

        f_train, f_test, t_train, t_test, w_train, w_test = train.split_train_test_data(
            features, target, wav_files, config)

        # Verify split
        self.assertEqual(len(f_train), 8)  # 80% of 10
        self.assertEqual(len(f_test), 2)  # 20% of 10
        self.assertEqual(len(t_train), 8)
        self.assertEqual(len(t_test), 2)
        self.assertEqual(len(w_train), 8)
        self.assertEqual(len(w_test), 2)

    def test_split_train_test_data_without_wav_files(self):
        """Test train/test splitting without wav files."""
        features = pd.DataFrame({'mfcc_1': [1.0, 2.0, 3.0, 4.0]})
        target = pd.Series(['A', 'B', 'A', 'B'])

        f_train, f_test, t_train, t_test, w_train, w_test = train.split_train_test_data(
            features, target, None)

        # Verify split
        self.assertEqual(len(f_train), 3)  # ~90% of 4
        self.assertEqual(len(f_test), 1)  # ~10% of 4
        self.assertIsNone(w_train)
        self.assertIsNone(w_test)

    def test_save_training_data(self):
        """Test saving training data to files."""
        # Create test data
        features_train = pd.DataFrame({'mfcc_1': [1.0, 2.0], 'mfcc_2': [3.0, 4.0]})
        target_train = pd.DataFrame({'speaker': ['A', 'B']})
        features_test = pd.DataFrame({'mfcc_1': [5.0], 'mfcc_2': [6.0]})
        target_test = pd.DataFrame({'speaker': ['C']})
        wav_files_test = pd.Series(['test.wav'])
        target_test_series = pd.Series(['C'])

        input_prefix = 'train_data'
        output_prefix = 'test_data'

        files_created = train.save_training_data(
            features_train, target_train, features_test, target_test,
            input_prefix, output_prefix, wav_files_test, target_test_series)

        # Verify files were created
        self.assertEqual(len(files_created), 5)  # 4 main files + 1 mapping

        for file_path in files_created:
            self.assertFileExists(file_path)

        # Verify mapping file content
        mapping_file = f'{output_prefix}_test_mapping.csv'
        self.assertFileExists(mapping_file)
        mapping_df = pd.read_csv(mapping_file)
        self.assertIn('speaker', mapping_df.columns)
        self.assertIn('wav_file', mapping_df.columns)

    def test_setup_test_directory(self):
        """Test test directory setup."""
        test_dir = os.path.join(self.test_dir, 'test_wav_dir')

        # Create directory first
        os.makedirs(test_dir, exist_ok=True)
        self.create_test_file(os.path.join(test_dir, 'existing.wav'), 'test')

        # Setup should remove and recreate
        result_dir = train.setup_test_directory(test_dir)

        self.assertEqual(result_dir, test_dir)
        self.assertDirectoryExists(test_dir)
        # Old file should be gone
        self.assertFalse(os.path.exists(os.path.join(test_dir, 'existing.wav')))

    def test_copy_test_wav_files(self):
        """Test WAV file copying function."""
        # Create source structure
        wav_dir = self.create_test_directory('source_wav')
        speaker_dir = self.create_test_directory('source_wav/21525')
        self.create_test_file('source_wav/21525/test1.wav', 'mock wav data')
        self.create_test_file('source_wav/21525/test2.wav', 'mock wav data')

        # Create destination
        test_wav_dir = self.create_test_directory('test_wav')

        # Test copying
        target_test = ['21525', '21525']
        wav_files_test = ['test1.wav', 'missing.wav']  # One exists, one doesn't

        stats = train.copy_test_wav_files(target_test, wav_files_test, wav_dir, test_wav_dir)

        # Verify results
        self.assertEqual(stats['files_copied'], 1)
        self.assertEqual(stats['files_not_found'], 1)

        # Verify copied file exists
        copied_file = os.path.join(test_wav_dir, '21525', 'test1.wav')
        self.assertFileExists(copied_file)


class TestTrainModelFunction(SafeTestCase):
    """Test the model training functions."""

    @skip_if_missing_dependency('sklearn')
    def test_train_model_basic(self):
        """Test basic model training function."""
        # Create test data
        features = pd.DataFrame({
            'mfcc_1': [1.0, 2.0, 3.0, 4.0, 5.0],
            'mfcc_2': [2.0, 3.0, 4.0, 5.0, 6.0]
        })
        target = pd.Series(['A', 'B', 'A', 'B', 'A'])

        config = {'enable_spinner': False, 'n_estimators': 10}

        model, training_time = train.train_model(features, target, n_estimators=10, config=config)

        # Verify results
        self.assertIsNotNone(model)
        self.assertIsInstance(training_time, float)
        self.assertGreater(training_time, 0)

        # Test model can predict
        predictions = model.predict(features)
        self.assertEqual(len(predictions), len(target))

    @skip_if_missing_dependency('sklearn')
    def test_train_with_progress_compatibility(self):
        """Test backward compatibility function."""
        features = pd.DataFrame({'mfcc_1': [1.0, 2.0], 'mfcc_2': [3.0, 4.0]})
        target = pd.Series(['A', 'B'])

        # Should work without config parameter
        model = train.train_with_progress(features, target, n_estimators=5)

        self.assertIsNotNone(model)
        predictions = model.predict(features)
        self.assertEqual(len(predictions), 2)


class TestTrainPipeline(SafeTestCase):
    """Test the complete training pipeline."""

    @skip_if_missing_dependency('sklearn')
    @patch('train.joblib.dump')
    def test_train_model_pipeline(self, mock_dump):
        """Test complete training pipeline."""
        # Create test CSV file
        csv_content = """speaker,wav_file,mfcc_1,mfcc_2,mfcc_3
21525,test1.wav,1.0,2.0,3.0
23723,test2.wav,4.0,5.0,6.0
21525,test3.wav,7.0,8.0,9.0
23723,test4.wav,10.0,11.0,12.0
21525,test5.wav,13.0,14.0,15.0
23723,test6.wav,16.0,17.0,18.0"""

        input_csv = self.create_test_file('training.csv', csv_content)

        # Create WAV source directory
        wav_dir = self.create_test_directory('wav_source')
        speaker_dir = self.create_test_directory('wav_source/21525')
        self.create_test_file('wav_source/21525/test1.wav', 'mock wav')
        self.create_test_file('wav_source/21525/test3.wav', 'mock wav')
        self.create_test_file('wav_source/21525/test5.wav', 'mock wav')

        output_prefix = 'test_output'
        model_file = 'test_model.pkl'

        config = {
            'enable_spinner': False,
            'n_estimators': 5,
            'test_size': 0.3,
            'random_state': 42
        }

        results = train.train_model_pipeline(input_csv, output_prefix, model_file, wav_dir, config)

        # Verify results structure
        self.assertIn('model', results)
        self.assertIn('training_time', results)
        self.assertIn('train_samples', results)
        self.assertIn('test_samples', results)
        self.assertIn('files_created', results)
        self.assertIn('copy_stats', results)

        # Verify some files were created
        self.assertGreater(len(results['files_created']), 0)

        # Verify model was "saved" (mocked)
        mock_dump.assert_called_once()

        # Verify test directory was created
        test_wav_dir = f'{output_prefix}_wav'
        self.assertDirectoryExists(test_wav_dir)


class TestTrainErrorHandling(SafeTestCase):
    """Test error handling in train functions."""

    def test_invalid_csv_file(self):
        """Test behavior with invalid CSV file."""
        with self.assertRaises(FileNotFoundError):
            train.train_model_pipeline('nonexistent.csv', 'output', 'model.pkl', 'wav_dir')

    def test_missing_wav_directory(self):
        """Test behavior with missing WAV directory."""
        # Create valid CSV with enough samples for splitting
        csv_content = """speaker,wav_file,mfcc_1
21525,test1.wav,1.0
23723,test2.wav,2.0
21525,test3.wav,3.0
23723,test4.wav,4.0
21525,test5.wav,5.0"""

        input_csv = self.create_test_file('test.csv', csv_content)

        config = {'enable_spinner': False, 'n_estimators': 5, 'test_size': 0.2}

        # Should not crash, but will report missing files
        results = train.train_model_pipeline(
            input_csv, 'output', 'model.pkl', 'nonexistent_wav_dir', config)

        # Should complete but report missing files (1 test sample)
        self.assertEqual(results['copy_stats']['files_not_found'], 1)
        self.assertEqual(results['copy_stats']['files_copied'], 0)


class TestTrainCLI(SafeTestCase):
    """Test command-line interface."""

    def test_cli_insufficient_args(self):
        """Test CLI with insufficient arguments."""
        import subprocess

        result = subprocess.run([
            'python3', f'{self.project_root}/train.py'
        ], capture_output=True, text=True, cwd=self.test_dir)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Usage:', result.stdout + result.stderr)

    def test_cli_valid_args_structure(self):
        """Test CLI with valid argument structure."""
        import subprocess

        # Create minimal test data
        csv_content = """speaker,wav_file,mfcc_1
21525,test.wav,1.0"""

        input_csv = self.create_test_file('train.csv', csv_content)
        wav_dir = self.create_test_directory('wav_dir')

        result = subprocess.run([
            'python3', f'{self.project_root}/train.py',
            input_csv, 'output', 'model.pkl', wav_dir
        ], capture_output=True, text=True, cwd=self.test_dir)

        # Should not show usage error (args parsed correctly)
        output = result.stdout + result.stderr
        if 'Usage:' in output:
            self.fail(f"CLI showed usage error with valid arguments: {output}")


if __name__ == '__main__':
    unittest.main()