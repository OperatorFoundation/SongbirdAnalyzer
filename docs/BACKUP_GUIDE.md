# Data Protection and Backup Guide

## Overview

The Songbird evaluation system includes comprehensive data protection features to prevent accidental loss of valuable audio recordings and training data. This guide covers the backup system, safety features, and recovery procedures.

## 🛡️ Safety Features

### Automatic Backup Protection

The system automatically protects two critical directories:
- **`working-evaluation/`** - Recorded modified audio from Teensy hardware (irreplaceable)
- **`working-training/`** - Processed training data (regenerable but time-consuming)

### Key Safety Mechanisms

- **Pre-destruction Backups**: Automatic backup creation before any destructive operations
- **User Confirmation**: Interactive prompts with clear options (unless `--force` used)
- **Retention Management**: Automatic cleanup keeps only the most recent backups
- **Audit Trail**: Complete log of all backup operations

## 📁 Backup System Architecture

### Directory Structure
```
backups/ 
├── working-evaluation_20250603_143022/ # Timestamped backups 
├── working-evaluation_20250603_150815/ # (most recent first) 
├── working-training_20250603_143025/ 
├── working-training_20250603_150820/ 
└── backup_log.txt # Operation audit trail
``` 
### Naming Convention
```
{directory-type}_{YYYYMMDD}_{HHMMSS}
``` 

### Configuration

| Setting | Default | Description |
|---------|---------|-------------|
| `MAX_BACKUPS_TO_KEEP` | `2` | Number of backups retained per directory |
| `BACKUP_ROOT_DIR` | `backups` | Root directory for all backups |
| `BACKUP_TIMESTAMP_FORMAT` | `%Y%m%d_%H%M%S` | Timestamp format for backup names |

## 🚀 Usage Scenarios

### Interactive Mode (Recommended)

When existing data is found, the system prompts for user decision:

**For Evaluation Data (irreplaceable recordings):**
```
bash ./evaluation-setup-environment.sh
# Output:
⚠️ WARNING: Existing working directory found: working-evaluation Directory contains 847 files that will be lost if we proceed.
Options: y) Create backup and proceed n) Cancel operation
f) Force proceed without backup (⚠️ DATA WILL BE LOST)
Your choice (y/n/f): y
``` 

**For Training Data (regenerable):**
```
bash ./splitall.sh audio/training working-training
# Output:
⚠️ WARNING: Existing training working directory found: working-training Directory contains 1,234 files that will be regenerated.
Training data can be regenerated, but backup is available for safety. Options: y) Create backup and proceed n) Cancel operation s) Skip backup and proceed (training data is regenerable)
Your choice (y/n/s): s
``` 

### Force Mode (Automation)

Use `--force` flag to skip prompts and automatically create backups:
```
bash
# Automatically backup and proceed
./evaluation-setup-environment.sh --force ./splitall.sh audio/training working-training --force
``` 

## 🔧 Backup Management Commands

### List Available Backups
```
bash ./backup-manager.sh list
# Output:
# Available backups in backups:
working-evaluation_20250603_150815 (2.3G) - Created: 2025-06-03 15:08:15 working-evaluation_20250603_143022 (2.1G) - Created: 2025-06-03 14:30:22 working-training_20250603_150820 (856M) - Created: 2025-06-03 15:08:20 working-training_20250603_143025 (834M) - Created: 2025-06-03 14:30:25 ================================================ Total backups found: 4
``` 

### Show Backup Statistics
```
bash ./backup-manager.sh stats
# Output:
# Backup Statistics:
Backup directory: backups Total backups: 4 Total backup size: 6.1G Max backups to keep: 2
Recent backup activity: 2025-06-03 15:08:20: Backup created - working-training_20250603_150820 2025-06-03 15:08:15: Backup created - working-evaluation_20250603_150815
``` 

### Restore a Backup
```
bash
# List available backups first
./backup-manager.sh list
# Restore specific backup
./backup-manager.sh restore working-evaluation_20250603_143022 working-evaluation
# Output:
WARNING: Target directory already exists: working-evaluation Restoration will overwrite existing content. Continue? (y/N): y Creating backup of current target before restoration... ✓ Existing data backed up successfully Restoring backup from backups/working-evaluation_20250603_143022 to working-evaluation... ✓ Backup restored successfully to: working-evaluation
``` 

### Manual Backup Creation
```
bash
# Create manual backup with custom name
./backup-manager.sh create working-evaluation my-important-session
# Output:
Creating backup of working-evaluation (2.3G)... Backup location: backups/my-important-session_20250603_160234 ✓ Backup created successfully: backups/my-important-session_20250603_160234
``` 

### Cleanup Old Backups
```
bash
# Clean up all old backups (keeps MAX_BACKUPS_TO_KEEP)
./backup-manager.sh cleanup
# Clean up backups for specific pattern
./backup-manager.sh cleanup working-evaluation
``` 

## ⚠️ Emergency Recovery

### Accidental Data Loss

If data is accidentally lost and you need to recover:

1. **Check for automatic backups:**
   ```bash
   ./backup-manager.sh list
   ```

2. **Restore the most recent backup:**
   ```bash
   ./backup-manager.sh restore working-evaluation_YYYYMMDD_HHMMSS working-evaluation
   ```

3. **Verify restoration:**
   ```bash
   ls -la working-evaluation/
   ```

### Process Interruption

If a long-running process is interrupted:

1. **Check partial results** - The system saves progress incrementally
2. **Review tracking reports** - Look for `modified_audio_tracking_report.txt`
3. **Consider restoration** - If data is corrupted, restore from backup
4. **Resume safely** - Use `--force` mode to skip prompts on restart

## 📊 Best Practices

### Before Important Operations

1. **Manual backup of critical data:**
   ```bash
   ./backup-manager.sh create working-evaluation pre-experiment-backup
   ```

2. **Check available disk space:**
   ```bash
   df -h .
   ./backup-manager.sh stats
   ```

### During Long Operations

1. **Monitor progress** - Watch for hardware disconnection warnings
2. **Don't interrupt unnecessarily** - Partial data can be valuable
3. **Check tracking reports** - Review progress periodically

### Regular Maintenance

1. **Review backup storage:**
   ```bash
   ./backup-manager.sh stats
   ```

2. **Clean up if needed:**
   ```bash
   ./backup-manager.sh cleanup
   ```

3. **Archive important backups** to external storage before cleanup

## 🔍 Troubleshooting

### "Backup Failed" Errors

**Cause**: Insufficient disk space or permission issues

**Solution**:
```
bash
# Check disk space
df -h .
# Check permissions
ls -la backups/
# Manual cleanup if needed
./backup-manager.sh cleanup
``` 

### "Directory Not Found" During Restore

**Cause**: Backup was manually deleted or corrupted

**Solution**:
```
bash
# List actual backups
ls -la backups/
# Use exact backup name from listing
./backup-manager.sh restore exact_backup_name target_directory
``` 

### "Cannot Proceed Without Backup" Errors

**Cause**: Backup creation failed but data protection is enforced

**Solution**:
```
bash
# Check disk space first
df -h .
# Try manual backup
./backup-manager.sh create working-evaluation manual-backup
# If manual backup works, retry operation
``` 

## 📝 Backup Log Analysis

The system maintains a detailed log at `backups/backup_log.txt`:
```
bash
# View recent backup activity
tail -20 backups/backup_log.txt
# Search for specific operations
grep "restored" backups/backup_log.txt grep "2025-06-03" backups/backup_log.txt
```