#!/usr/bin/env python3

"""
Songbird Audio Validation Module

Provides audio file validation.
Handles file format validation, duration checking, content analysis, etc.
"""

import os
import sys
import wave
import json
import logging
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Union
from dataclasses import dataclass
from datetime import datetime

try:
    import librosa
    import numpy as np

    HAS_LIBROSA = True
except ImportError:
    HAS_LIBROSA = False
    print("Warning: librosa not available. Audio analysis will be limited.", file=sys.stderr)


@dataclass
class ValidationResult:
    """Result of audio file validation"""
    is_valid: bool
    file_path: str
    file_size: int
    duration: Optional[float] = None
    sample_rate: Optional[int] = None
    channels: Optional[int] = None
    format_info: Optional[str] = None
    issues: List[str] = None
    validation_time: str = None

    def __post_init__(self):
        if self.issues is None:
            self.issues = []
        if self.validation_time is None:
            self.validation_time = datetime.now().isoformat()


class AudioValidator:
    """Comprehensive audio file validator"""

    def __init__(self,
                 min_duration: float = 8.0,
                 max_duration: float = 12.0,
                 min_file_size: int = 1024,
                 expected_sample_rate: int = 44100,
                 tolerance_seconds: float = 2.0):
        """
        Initialize validator with configurable parameters

        Args:
            min_duration: Minimum acceptable duration in seconds
            max_duration: Maximum acceptable duration in seconds
            min_file_size: Minimum file size in bytes
            expected_sample_rate: Expected sample rate (Hz)
            tolerance_seconds: Tolerance for duration checking
        """
        self.min_duration = min_duration
        self.max_duration = max_duration
        self.min_file_size = min_file_size
        self.expected_sample_rate = expected_sample_rate
        self.tolerance_seconds = tolerance_seconds

        # Setup logging
        logging.basicConfig(level=logging.INFO)
        self.logger = logging.getLogger(__name__)

    def validate_file_exists(self, file_path: str) -> Tuple[bool, List[str]]:
        """Check if file exists and is accessible"""
        issues = []

        if not os.path.exists(file_path):
            issues.append(f"File does not exist: {file_path}")
            return False, issues

        if not os.path.isfile(file_path):
            issues.append(f"Path is not a file: {file_path}")
            return False, issues

        if not os.access(file_path, os.R_OK):
            issues.append(f"File is not readable: {file_path}")
            return False, issues

        return True, issues

    def validate_file_size(self, file_path: str) -> Tuple[bool, int, List[str]]:
        """Validate file size meets minimum requirements"""
        issues = []

        try:
            file_size = os.path.getsize(file_path)
        except OSError as e:
            issues.append(f"Cannot get file size: {e}")
            return False, 0, issues

        if file_size < self.min_file_size:
            issues.append(f"File too small: {file_size} bytes (minimum: {self.min_file_size})")
            return False, file_size, issues

        return True, file_size, issues

    def validate_audio_format_basic(self, file_path: str) -> Tuple[bool, Dict, List[str]]:
        """Basic audio format validation using wave module"""
        issues = []
        audio_info = {}

        try:
            with wave.open(file_path, 'rb') as wav_file:
                audio_info.update({
                    'channels': wav_file.getnchannels(),
                    'sample_width': wav_file.getsampwidth(),
                    'sample_rate': wav_file.getframerate(),
                    'frames': wav_file.getnframes(),
                    'duration': wav_file.getnframes() / wav_file.getframerate(),
                    'format': 'WAV'
                })
        except wave.Error as e:
            issues.append(f"Invalid WAV format: {e}")
            return False, audio_info, issues
        except Exception as e:
            issues.append(f"Cannot read audio file: {e}")
            return False, audio_info, issues

        return True, audio_info, issues

    def validate_audio_format_advanced(self, file_path: str) -> Tuple[bool, Dict, List[str]]:
        """Advanced audio format validation using librosa"""
        if not HAS_LIBROSA:
            return self.validate_audio_format_basic(file_path)

        issues = []
        audio_info = {}

        try:
            # Load audio file
            y, sr = librosa.load(file_path, sr=None)

            audio_info.update({
                'duration': librosa.get_duration(y=y, sr=sr),
                'sample_rate': sr,
                'samples': len(y),
                'channels': 1,  # librosa loads as mono by default
                'format': 'WAV (librosa validated)'
            })

            # Check for silence (very low amplitude)
            max_amplitude = np.max(np.abs(y))
            if max_amplitude < 0.001:
                issues.append(f"Audio appears to be silent (max amplitude: {max_amplitude:.6f})")

            # Check for clipping (values at or near ±1.0)
            clipping_threshold = 0.99
            clipped_samples = np.sum(np.abs(y) >= clipping_threshold)
            if clipped_samples > len(y) * 0.01:  # More than 1% clipped
                issues.append(f"Audio may be clipped ({clipped_samples} samples >= {clipping_threshold})")

        except Exception as e:
            issues.append(f"Cannot analyze audio with librosa: {e}")
            return False, audio_info, issues

        return True, audio_info, issues

    def validate_duration(self, duration: float) -> Tuple[bool, List[str]]:
        """Validate audio duration is within acceptable range"""
        issues = []

        if duration < (self.min_duration - self.tolerance_seconds):
            issues.append(
                f"Audio too short: {duration:.2f}s (minimum: {self.min_duration - self.tolerance_seconds:.2f}s)")
            return False, issues

        if duration > (self.max_duration + self.tolerance_seconds):
            issues.append(
                f"Audio too long: {duration:.2f}s (maximum: {self.max_duration + self.tolerance_seconds:.2f}s)")
            return False, issues

        return True, issues

    def validate_sample_rate(self, sample_rate: int) -> Tuple[bool, List[str]]:
        """Validate sample rate matches expected value"""
        issues = []

        if sample_rate != self.expected_sample_rate:
            issues.append(f"Unexpected sample rate: {sample_rate}Hz (expected: {self.expected_sample_rate}Hz)")
            # This is often not a fatal error, so we return True but note the issue

        return True, issues

    def validate_file(self, file_path: str) -> ValidationResult:
        """Comprehensive validation of a single audio file"""
        all_issues = []
        is_valid = True
        file_size = 0
        audio_info = {}

        # Step 1: Check file existence and accessibility
        exists_ok, exists_issues = self.validate_file_exists(file_path)
        all_issues.extend(exists_issues)
        if not exists_ok:
            return ValidationResult(
                is_valid=False,
                file_path=file_path,
                file_size=0,
                issues=all_issues
            )

        # Step 2: Check file size
        size_ok, file_size, size_issues = self.validate_file_size(file_path)
        all_issues.extend(size_issues)
        if not size_ok:
            is_valid = False

        # Step 3: Validate audio format and get basic info
        if HAS_LIBROSA:
            format_ok, audio_info, format_issues = self.validate_audio_format_advanced(file_path)
        else:
            format_ok, audio_info, format_issues = self.validate_audio_format_basic(file_path)

        all_issues.extend(format_issues)
        if not format_ok:
            is_valid = False

        # Step 4: Validate duration if we have it
        duration = audio_info.get('duration')
        if duration is not None:
            duration_ok, duration_issues = self.validate_duration(duration)
            all_issues.extend(duration_issues)
            if not duration_ok:
                is_valid = False

        # Step 5: Validate sample rate if we have it
        sample_rate = audio_info.get('sample_rate')
        if sample_rate is not None:
            sr_ok, sr_issues = self.validate_sample_rate(sample_rate)
            all_issues.extend(sr_issues)
            # Note: sample rate mismatches don't fail validation

        return ValidationResult(
            is_valid=is_valid,
            file_path=file_path,
            file_size=file_size,
            duration=duration,
            sample_rate=sample_rate,
            channels=audio_info.get('channels'),
            format_info=audio_info.get('format'),
            issues=all_issues
        )


def validate_audio_file(file_path: str,
                        expected_duration: float = 10.0,
                        tolerance: float = 2.0,
                        min_file_size: int = 1024) -> Dict:
    """
    Command-line interface for audio validation
    Returns validation result as dictionary for bash consumption
    """
    validator = AudioValidator(
        min_duration=expected_duration - tolerance,
        max_duration=expected_duration + tolerance,
        min_file_size=min_file_size,
        tolerance_seconds=tolerance
    )

    result = validator.validate_file(file_path)

    # Convert to dictionary for JSON serialization
    return {
        'is_valid': result.is_valid,
        'file_path': result.file_path,
        'file_size': result.file_size,
        'duration': result.duration,
        'sample_rate': result.sample_rate,
        'channels': result.channels,
        'format_info': result.format_info,
        'issues': result.issues,
        'validation_time': result.validation_time
    }


def main():
    """Command line interface"""
    if len(sys.argv) < 2:
        print("Usage: python3 validation.py <audio_file> [expected_duration] [tolerance] [min_file_size]")
        print("Example: python3 validation.py test.wav 10.0 2.0 1024")
        sys.exit(1)

    file_path = sys.argv[1]
    expected_duration = float(sys.argv[2]) if len(sys.argv) > 2 else 10.0
    tolerance = float(sys.argv[3]) if len(sys.argv) > 3 else 2.0
    min_file_size = int(sys.argv[4]) if len(sys.argv) > 4 else 1024

    result = validate_audio_file(file_path, expected_duration, tolerance, min_file_size)

    # Output as JSON for bash consumption
    print(json.dumps(result, indent=2))

    # Exit with appropriate code
    sys.exit(0 if result['is_valid'] else 1)


if __name__ == "__main__":
    main()