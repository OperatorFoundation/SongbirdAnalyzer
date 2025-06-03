**Training Flow:**
1. Download LibriVox MP3s ✅
2. Split to WAV segments in ✅ `working-training/`
3. Extract MFCC features → ✅ `results/training.csv`
4. Standardize features → `results/training_standardized.csv` ✅
5. Train model + create test split → + `results/testing_wav/` ✅ `songbird.pkl`

**Evaluation Flow:**
1. Read test files from `results/testing_wav/` ✅
2. Record modified audio → ✅ `working-evaluation/`
3. Extract MFCC from modified audio → ✅ `results/evaluation.csv`
4. Standardize to match training → `results/evaluation_standardized.csv` ✅
5. Analyze results using standardized data ✅
