## Songbird Pipeline Documentation
### Overview
The Songbird Pipeline is a voice analysis system that trains machine learning models on speaker recognition and evaluates them using modified audio (processed through hardware effects).
### Quick Reference Card
``` bash
# Essential Commands
./songbird-pipeline.sh help      # Show all options
./songbird-pipeline.sh status    # Check what's ready
./songbird-pipeline.sh training  # Train model (safe - no recording)
./songbird-pipeline.sh evaluation # ⚠️ RECORDS NEW AUDIO - OVERWRITES EXISTING
./songbird-pipeline.sh quick     # Re-analyze existing recorded audio (safe)
./songbird-pipeline.sh clean     # ⚠️ DELETES EVERYTHING - COMPLETE RESET
```
### ⚠️ CRITICAL: Modified Audio Safety
**Commands that PRESERVE your recorded modified audio:**
- ✅ `./songbird-pipeline.sh status`
- ✅ `./songbird-pipeline.sh training`
- ✅ `./songbird-pipeline.sh quick`
- ✅ `./songbird-pipeline.sh help`

**Commands that DESTROY/OVERWRITE your recorded modified audio:**
- ❌ `./songbird-pipeline.sh evaluation` (Records fresh audio, deletes existing)
- ❌ `./songbird-pipeline.sh full` (Includes evaluation step)
- ❌ `./songbird-pipeline.sh clean` (Deletes everything)

**Recovery:** Once modified audio is overwritten, it's **PERMANENTLY LOST**. There is no undo.
## Detailed Command Reference
### Safe Commands (No Recording Impact)
#### `./songbird-pipeline.sh status`
**Purpose:** Check current pipeline state
**Audio Impact:** 🟢 None - read-only operation
**Use when:** You want to see what's ready without changing anything
**Output example:**
``` 
📂 File Status:
  Training data ready: ✅
  Model trained: ✅  
  Test files prepared: ✅
  Modified audio recorded: ❌
```
#### `./songbird-pipeline.sh training`
**Purpose:** Download audio, train model, create test files
**Audio Impact:** 🟢 None - no recording involved
**Duration:** ~15-30 minutes
**Use when:** First time setup or retraining model
**What it does:**
1. Downloads LibriVox audiobooks (21525, 23723, 19839)
2. Splits audio into 10-second segments
3. Extracts MFCC features
4. Standardizes feature dimensions
5. Trains RandomForest model
6. Creates test dataset for evaluation

**Files created:**
- (trained model) `songbird.pkl`
- `results/training*.csv` (training data)
- `results/testing*.csv` (test data)
- `results/testing_wav/` (test audio files)
- `results/feature_dimensions.json` (standardization reference)

#### `./songbird-pipeline.sh quick`
**Purpose:** Re-analyze existing recorded modified audio
**Audio Impact:** 🟢 None - uses existing recordings
**Duration:** ~2-5 minutes
**Use when:** You want to re-run analysis without re-recording
**Prerequisites:** Must have existing recordings in `working-evaluation/`
**What it does:**
1. Extracts MFCC features from existing files `working-evaluation/`
2. Standardizes features to match training
3. Runs analysis and predictions

#### `./songbird-pipeline.sh help`
**Purpose:** Show usage information
**Audio Impact:** 🟢 None
### Destructive Commands (Will Record/Delete Audio)
#### `./songbird-pipeline.sh evaluation` ⚠️
**Purpose:** Record fresh modified audio and analyze it
**Audio Impact:** 🔴 **DESTRUCTIVE - Deletes existing recordings**
**Duration:** ~20-45 minutes (depends on hardware interaction)
**Use when:** You want fresh recordings with current hardware setup
**⚠️ WARNING:** This command will:
1. **DELETE** the entire directory `working-evaluation/`
2. **RECORD NEW** modified audio using Teensy device
3. Process and analyze the new recordings

**Prerequisites:**
- Teensy device connected and working
- installed (`brew install switchaudio-osx`) `SwitchAudioSource`
- Completed training first

**Manual intervention required:**
- You must physically interact with the recording process
- May need to press buttons or adjust hardware settings
- Can be interrupted with Ctrl+C (partial results saved)

#### `./songbird-pipeline.sh full` ⚠️
**Purpose:** Complete pipeline from scratch
**Audio Impact:** 🔴 **DESTRUCTIVE if evaluation runs**
**Duration:** ~45-75 minutes
**Use when:** Complete fresh start
**Note:** This runs training then STOPS before evaluation. It will prompt you to run evaluation separately.
#### `./songbird-pipeline.sh clean` ⚠️
**Purpose:** Delete all generated files and start fresh
**Audio Impact:** 🔴 **COMPLETELY DESTRUCTIVE**
**Duration:** ~10 seconds
**Use when:** You want to completely reset the project
**⚠️ WARNING:** This command deletes:
- All recorded modified audio () `working-evaluation/`
- All training results (`results/*.csv`)
- Trained model () `songbird.pkl`
- All temporary files

## Typical Workflows
### First Time Setup
``` bash
# 1. Train the model (safe)
./songbird-pipeline.sh training

# 2. Check everything is ready (safe)  
./songbird-pipeline.sh status

# 3. Connect Teensy device, then record (destructive)
./songbird-pipeline.sh evaluation
```
### Experiment with Hardware Settings
``` bash
# 1. Check current status (safe)
./songbird-pipeline.sh status

# 2. If you want to try new hardware settings, record fresh audio (destructive)
./songbird-pipeline.sh evaluation

# 3. If you just want to re-analyze existing recordings (safe)
./songbird-pipeline.sh quick
```
### Development/Testing Cycle
``` bash
# Safe: Modify analysis code, then re-analyze existing recordings
./songbird-pipeline.sh quick

# Safe: Check results
./songbird-pipeline.sh status

# Only when needed: Record new audio with hardware changes (destructive)
./songbird-pipeline.sh evaluation
```
### Complete Reset
``` bash
# Nuclear option - deletes everything (destructive)
./songbird-pipeline.sh clean

# Start fresh (safe)
./songbird-pipeline.sh training
```
## File Structure Guide
### Input Files (Your Audio)
``` 
audio/training/21525/    # LibriVox speaker 21525 files
audio/training/23723/    # LibriVox speaker 23723 files  
audio/training/19839/    # LibriVox speaker 19839 files
```
### Generated Files (Safe to Delete)
``` 
working-training/        # Temporary training audio segments
working-evaluation/      # ⚠️ YOUR RECORDED MODIFIED AUDIO
results/                 # All CSV files and analysis results
songbird.pkl            # Trained model
feature_dimensions.json  # Standardization reference
*.txt                   # Tracking reports
```
### Critical Files to Backup
If you have successful recordings you want to preserve:
``` bash
# Backup your precious recorded audio
cp -r working-evaluation/ backup-recordings-$(date +%Y%m%d)/

# Backup your trained model
cp songbird.pkl backup-model-$(date +%Y%m%d).pkl
```
## Error Recovery
### "No modified audio found"
Running but no recordings exist
**Solution:** Run `evaluation` to record fresh audio (destructive) **Error:**`quick`
### "No trained model found"
Trying evaluation without training first
**Solution:** Run `training` first (safe) **Error:**
### "Teensy device not found"
Evaluation can't find hardware
**Solution:** **Error:**
1. Check USB connection
2. Verify device permissions
3. Try different USB port

### "Feature dimension mismatch"
Training and evaluation have different feature counts
**Solution:** Pipeline now auto-standardizes - this shouldn't happen **Error:**
### Interrupted Recording
**What happens:** Ctrl+C during evaluation saves partial results
**Recovery:** Check for what was completed
**Options:** `modified_audio_tracking_report.txt`
- Run to analyze partial results `quick`
- Run `evaluation` again to start fresh recording (destructive)

## Performance Tips
### Speed Up Development
- Use for code changes (doesn't re-record) `quick`
- Only use `evaluation` when hardware changes
- Keep backups of good recordings

### Save Time on Training
- Training downloads ~500MB of audio - only run when needed
- Downloaded files are cached in `audio/training/`
- Model training is deterministic - same data = same model

### Monitor Resource Usage
- Recording uses microphone and speakers simultaneously
- Large files created in (can be GB) `working-evaluation/`
- Training uses significant CPU for RandomForest

## Troubleshooting Quick Reference

| Problem | Safe Solution | Destructive Solution |
| --- | --- | --- |
| Want to re-analyze results | `quick` | - |
| Changed analysis code | `quick` | - |
| Hardware settings changed | - | `evaluation` |
| Model seems wrong | `training` | - |
| Everything broken | - | `clean` then `training` |
| Out of disk space | Check size `working-evaluation/` | `clean` |
**Remember:** When in doubt, use `status` first to see what you have, then to re-analyze safely! `quick`

