"""Simple, focused tests for standardize_features.py functionality."""
import unittest
import os
import pandas as pd
import json
import sys

# Add project root to path for imports
sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__)))))

from tests.helpers.test_helpers import SafeTestCase
import standardize_features


class TestStandardizeFeaturesCoreFunctions(SafeTestCase):
    """Test the core extracted functions from standardize_features.py."""

    def test_categorize_columns(self):
        """Test column categorization function."""
        columns = [
            'speaker', 'wav_file',
            'MFCC_1', 'MFCC_2', 'MFCC_10',
            'Delta_1', 'Delta_3', 'Delta_2',
            'Delta2_1', 'Delta2_2'
        ]

        categories = standardize_features.categorize_columns(columns)

        # Verify structure
        self.assertIn('MFCC', categories)
        self.assertIn('Delta', categories)
        self.assertIn('Delta2', categories)

        # Verify content
        self.assertEqual(len(categories['MFCC']), 3)
        self.assertEqual(len(categories['Delta']), 3)
        self.assertEqual(len(categories['Delta2']), 2)

        # Verify sorting (should be numeric order)
        self.assertEqual(categories['MFCC'], ['MFCC_1', 'MFCC_2', 'MFCC_10'])
        self.assertEqual(categories['Delta'], ['Delta_1', 'Delta_2', 'Delta_3'])

    def test_categorize_columns_empty(self):
        """Test column categorization with no feature columns."""
        columns = ['speaker', 'wav_file', 'mode']

        categories = standardize_features.categorize_columns(columns)

        self.assertEqual(len(categories['MFCC']), 0)
        self.assertEqual(len(categories['Delta']), 0)
        self.assertEqual(len(categories['Delta2']), 0)

    def test_extract_reference_dimensions(self):
        """Test extracting reference dimensions from DataFrame."""
        df = pd.DataFrame({
            'speaker': ['A', 'B'],
            'MFCC_1': [1.0, 2.0],
            'MFCC_2': [3.0, 4.0],
            'Delta_1': [5.0, 6.0],
            'Delta2_1': [7.0, 8.0],
            'Delta2_2': [9.0, 10.0]
        })

        reference_dims = standardize_features.extract_reference_dimensions(df)

        self.assertEqual(reference_dims['MFCC'], 2)
        self.assertEqual(reference_dims['Delta'], 1)
        self.assertEqual(reference_dims['Delta2'], 2)

    def test_get_standardized_columns(self):
        """Test determining columns to keep for standardization."""
        df = pd.DataFrame({
            'speaker': ['A', 'B'],
            'wav_file': ['f1.wav', 'f2.wav'],
            'MFCC_1': [1.0, 2.0],
            'MFCC_2': [3.0, 4.0],
            'MFCC_3': [5.0, 6.0],  # Extra column
            'Delta_1': [7.0, 8.0],
            'Delta2_1': [9.0, 10.0]
        })

        reference_dims = {'MFCC': 2, 'Delta': 1, 'Delta2': 1}

        columns_to_keep, info = standardize_features.get_standardized_columns(df, reference_dims)

        # Should keep metadata columns
        self.assertIn('speaker', columns_to_keep)
        self.assertIn('wav_file', columns_to_keep)

        # Should keep only reference number of feature columns
        mfcc_cols = [col for col in columns_to_keep if col.startswith('MFCC_')]
        self.assertEqual(len(mfcc_cols), 2)

        # Should have trimming info for MFCC
        self.assertIn('MFCC', info['trimmed'])
        self.assertEqual(info['trimmed']['MFCC']['from'], 3)
        self.assertEqual(info['trimmed']['MFCC']['to'], 2)

    def test_get_standardized_columns_with_warnings(self):
        """Test standardization with insufficient columns."""
        df = pd.DataFrame({
            'speaker': ['A'],
            'MFCC_1': [1.0],
            'Delta_1': [2.0]
        })

        reference_dims = {'MFCC': 3, 'Delta': 1, 'Delta2': 2}  # More than available

        columns_to_keep, info = standardize_features.get_standardized_columns(df, reference_dims)

        # Should have warnings for insufficient columns
        self.assertEqual(len(info['warnings']), 2)  # MFCC and Delta2

        warning_categories = [w['category'] for w in info['warnings']]
        self.assertIn('MFCC', warning_categories)
        self.assertIn('Delta2', warning_categories)

    def test_standardize_dataframe_to_dimensions(self):
        """Test DataFrame standardization."""
        df = pd.DataFrame({
            'speaker': ['A', 'B'],
            'MFCC_1': [1.0, 2.0],
            'MFCC_2': [3.0, 4.0],
            'MFCC_3': [5.0, 6.0],
            'Delta_1': [7.0, 8.0]
        })

        reference_dims = {'MFCC': 2, 'Delta': 1, 'Delta2': 0}

        df_standardized, info = standardize_features.standardize_dataframe_to_dimensions(df, reference_dims)

        # Should have correct shape
        self.assertEqual(df_standardized.shape[0], 2)  # Same rows
        self.assertEqual(df_standardized.shape[1], 4)  # speaker + 2 MFCC + 1 Delta

        # Should contain expected columns
        self.assertIn('speaker', df_standardized.columns)
        self.assertIn('MFCC_1', df_standardized.columns)
        self.assertIn('MFCC_2', df_standardized.columns)
        self.assertNotIn('MFCC_3', df_standardized.columns)  # Trimmed

    def test_save_and_load_reference_dimensions(self):
        """Test saving and loading reference dimensions."""
        reference_dims = {'MFCC': 13, 'Delta': 13, 'Delta2': 13}
        reference_file = os.path.join(self.test_dir, 'test_reference.json')

        # Test saving
        saved_path = standardize_features.save_reference_dimensions(reference_dims, reference_file)
        self.assertEqual(saved_path, reference_file)
        self.assertFileExists(reference_file)

        # Test loading
        loaded_dims = standardize_features.load_reference_dimensions(reference_file)
        self.assertEqual(loaded_dims, reference_dims)

    def test_load_reference_dimensions_missing_file(self):
        """Test loading reference dimensions from non-existent file."""
        with self.assertRaises(FileNotFoundError):
            standardize_features.load_reference_dimensions('nonexistent.json')

    def test_standardize_file_to_training_dimensions(self):
        """Test standardizing a CSV file."""
        # Create test CSV file
        df = pd.DataFrame({
            'speaker': ['A', 'B'],
            'wav_file': ['f1.wav', 'f2.wav'],
            'MFCC_1': [1.0, 2.0],
            'MFCC_2': [3.0, 4.0],
            'MFCC_3': [5.0, 6.0],
            'Delta_1': [7.0, 8.0]
        })

        input_file = self.create_test_file('test_input.csv')
        df.to_csv(input_file, index=False)

        reference_dims = {'MFCC': 2, 'Delta': 1, 'Delta2': 0}
        config = {'enable_printing': False}

        output_path, shape, info = standardize_features.standardize_file_to_training_dimensions(
            input_file, reference_dims, config)

        # Verify output file was created
        self.assertFileExists(output_path)
        self.assertTrue(output_path.endswith('_standardized.csv'))

        # Verify shape - should have speaker, wav_file, MFCC_1, MFCC_2, Delta_1 = 5 columns
        self.assertEqual(shape[0], 2)  # Same number of rows
        self.assertEqual(shape[1], 5)  # speaker, wav_file, MFCC_1, MFCC_2, Delta_1

        # Verify content
        df_result = pd.read_csv(output_path)
        self.assertIn('MFCC_1', df_result.columns)
        self.assertNotIn('MFCC_3', df_result.columns)

    def test_print_standardization_info(self):
        """Test printing standardization information."""
        import io
        from contextlib import redirect_stdout

        info = {
            'trimmed': {'MFCC': {'from': 15, 'to': 13}},
            'warnings': [{'category': 'Delta', 'available': 10, 'expected': 13}],
            'missing_columns': ['MFCC_14', 'MFCC_15']
        }

        # Capture printed output
        captured_output = io.StringIO()
        with redirect_stdout(captured_output):
            standardize_features.print_standardization_info(info, 'test.csv')

        output = captured_output.getvalue()

        # Verify key information is printed
        self.assertIn('test.csv', output)
        self.assertIn('Trimmed MFCC: 15 → 13', output)
        self.assertIn('Delta has fewer columns', output)
        self.assertIn('Missing columns', output)


class TestStandardizeFeaturesProcessingModes(SafeTestCase):
    """Test the processing mode functions."""

    def test_process_training_mode(self):
        """Test training mode processing."""
        # Create training data
        df = pd.DataFrame({
            'speaker': ['A', 'B', 'C'],
            'wav_file': ['f1.wav', 'f2.wav', 'f3.wav'],
            'MFCC_1': [1.0, 2.0, 3.0],
            'MFCC_2': [4.0, 5.0, 6.0],
            'Delta_1': [7.0, 8.0, 9.0],
            'Delta2_1': [10.0, 11.0, 12.0]
        })

        training_file = self.create_test_file('training.csv')
        df.to_csv(training_file, index=False)

        config = {
            'enable_printing': False,
            'output_dir': self.test_dir
        }

        results = standardize_features.process_training_mode(training_file, config)

        # Verify results structure
        self.assertIn('reference_dims', results)
        self.assertIn('output_file', results)
        self.assertIn('reference_file', results)

        # Verify reference dimensions
        expected_dims = {'MFCC': 2, 'Delta': 1, 'Delta2': 1}
        self.assertEqual(results['reference_dims'], expected_dims)

        # Verify files were created
        self.assertFileExists(results['output_file'])
        self.assertFileExists(results['reference_file'])

        # Verify content - should have speaker, wav_file, MFCC_1, MFCC_2, Delta_1, Delta2_1 = 6 columns
        df_output = pd.read_csv(results['output_file'])
        self.assertEqual(df_output.shape, (3, 6))  # All columns preserved in training

    def test_process_training_mode_missing_file(self):
        """Test training mode with missing file."""
        config = {'enable_printing': False}

        with self.assertRaises(FileNotFoundError):
            standardize_features.process_training_mode('nonexistent.csv', config)

    def test_process_evaluation_mode(self):
        """Test evaluation mode processing."""
        # Create reference dimensions file
        reference_dims = {'MFCC': 2, 'Delta': 1, 'Delta2': 0}
        reference_file = os.path.join(self.test_dir, 'reference.json')
        standardize_features.save_reference_dimensions(reference_dims, reference_file)

        # Create evaluation data (with extra MFCC column)
        df = pd.DataFrame({
            'speaker': ['A', 'B'],
            'wav_file': ['f1.wav', 'f2.wav'],
            'MFCC_1': [1.0, 2.0],
            'MFCC_2': [3.0, 4.0],
            'MFCC_3': [5.0, 6.0],  # Extra column
            'Delta_1': [7.0, 8.0],
            'Delta2_1': [9.0, 10.0]  # Should be excluded
        })

        evaluation_file = self.create_test_file('evaluation.csv')
        df.to_csv(evaluation_file, index=False)

        config = {'enable_printing': False}

        results = standardize_features.process_evaluation_mode(
            evaluation_file, reference_file, config)

        # Verify results
        self.assertIn('output_path', results)
        self.assertIn('standardized_shape', results)

        # Verify output file
        self.assertFileExists(results['output_path'])

        # Verify standardized shape - should have speaker, wav_file, MFCC_1, MFCC_2, Delta_1 = 5 columns
        self.assertEqual(results['standardized_shape'], (2, 5))

        # Verify content
        df_output = pd.read_csv(results['output_path'])
        self.assertNotIn('MFCC_3', df_output.columns)  # Should be trimmed
        self.assertNotIn('Delta2_1', df_output.columns)  # Should be excluded

    def test_process_evaluation_mode_missing_reference(self):
        """Test evaluation mode with missing reference file."""
        config = {'enable_printing': False}

        with self.assertRaises(FileNotFoundError):
            standardize_features.process_evaluation_mode(
                'eval.csv', 'nonexistent_reference.json', config)

    def test_process_evaluation_mode_missing_evaluation_file(self):
        """Test evaluation mode with missing evaluation file."""
        # Create reference file
        reference_dims = {'MFCC': 2, 'Delta': 1, 'Delta2': 0}
        reference_file = os.path.join(self.test_dir, 'reference.json')
        standardize_features.save_reference_dimensions(reference_dims, reference_file)

        config = {'enable_printing': False}

        with self.assertRaises(FileNotFoundError):
            standardize_features.process_evaluation_mode(
                'nonexistent_eval.csv', reference_file, config)


class TestStandardizeFeaturesPipeline(SafeTestCase):
    """Test the main pipeline function."""

    def test_standardize_features_pipeline_training(self):
        """Test complete training pipeline."""
        # Create training data
        df = pd.DataFrame({
            'speaker': ['A', 'B'],
            'MFCC_1': [1.0, 2.0],
            'MFCC_2': [3.0, 4.0],
            'Delta_1': [5.0, 6.0]
        })

        training_file = os.path.join(self.test_dir, 'training.csv')
        df.to_csv(training_file, index=False)

        config = {
            'enable_printing': False,
            'training_file': training_file,
            'output_dir': self.test_dir
        }

        results = standardize_features.standardize_features_pipeline('training', config)

        self.assertIn('reference_dims', results)
        self.assertEqual(results['reference_dims']['MFCC'], 2)
        self.assertEqual(results['reference_dims']['Delta'], 1)

    def test_standardize_features_pipeline_evaluation(self):
        """Test complete evaluation pipeline."""
        # Setup training reference
        reference_dims = {'MFCC': 1, 'Delta': 1, 'Delta2': 0}
        reference_file = os.path.join(self.test_dir, 'reference.json')
        standardize_features.save_reference_dimensions(reference_dims, reference_file)

        # Create evaluation data
        df = pd.DataFrame({
            'speaker': ['A'],
            'MFCC_1': [1.0],
            'MFCC_2': [2.0],  # Extra column
            'Delta_1': [3.0]
        })

        evaluation_file = os.path.join(self.test_dir, 'evaluation.csv')
        df.to_csv(evaluation_file, index=False)

        config = {
            'enable_printing': False,
            'evaluation_file': evaluation_file,
            'reference_file': reference_file
        }

        results = standardize_features.standardize_features_pipeline('evaluation', config)

        self.assertIn('output_path', results)
        self.assertEqual(results['standardized_shape'], (1, 3))  # speaker, MFCC_1, Delta_1

    def test_standardize_features_pipeline_invalid_mode(self):
        """Test pipeline with invalid mode."""
        with self.assertRaises(ValueError):
            standardize_features.standardize_features_pipeline('invalid_mode')


class TestStandardizeFeaturesCLI(SafeTestCase):
    """Test command-line interface."""

    def test_cli_insufficient_args(self):
        """Test CLI with insufficient arguments."""
        import subprocess

        result = subprocess.run([
            'python3', f'{self.project_root}/standardize_features.py'
        ], capture_output=True, text=True, cwd=self.test_dir)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Usage:', result.stdout + result.stderr)

    def test_cli_training_mode(self):
        """Test CLI training mode."""
        import subprocess

        # Create minimal training data
        df = pd.DataFrame({
            'speaker': ['A'],
            'MFCC_1': [1.0]
        })

        # Create results directory and training file
        results_dir = self.create_test_directory('results')
        training_file = os.path.join(results_dir, 'training.csv')
        df.to_csv(training_file, index=False)

        result = subprocess.run([
            'python3', f'{self.project_root}/standardize_features.py',
            'training'
        ], capture_output=True, text=True, cwd=self.test_dir)

        # Should run successfully
        self.assertEqual(result.returncode, 0)

        # Should create expected output files
        self.assertFileExists(os.path.join(results_dir, 'training_standardized.csv'))
        self.assertFileExists(os.path.join(results_dir, 'feature_dimensions.json'))

    def test_cli_invalid_mode(self):
        """Test CLI with invalid mode."""
        import subprocess

        result = subprocess.run([
            'python3', f'{self.project_root}/standardize_features.py',
            'invalid'
        ], capture_output=True, text=True, cwd=self.test_dir)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Unknown mode', result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()