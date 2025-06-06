#!/usr/bin/env python3

"""
Songbird Checkpoint Management System

Handles checkpoint creation, validation, and recovery for recording sessions.
"""

import os
import json
import sys
import csv
import hashlib
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional, Set, Tuple
from dataclasses import dataclass, asdict
from enum import Enum


class TaskStatus(Enum):
    """Status of a recording task"""
    PENDING = "PENDING"
    COMPLETED = "COMPLETED"
    FAILED = "FAILED"
    SKIPPED = "SKIPPED"
    IN_PROGRESS = "IN_PROGRESS"


@dataclass
class RecordingTask:
    """Represents a single recording task"""
    speaker: str
    mode_name: str
    source_filename: str
    output_path: str
    status: TaskStatus = TaskStatus.PENDING
    timestamp: str = None
    error_message: str = None
    validation_result: Dict = None

    def __post_init__(self):
        if self.timestamp is None:
            self.timestamp = datetime.now().isoformat()

    @property
    def task_id(self) -> str:
        """Generate unique task identifier"""
        task_string = f"{self.speaker}|{self.mode_name}|{self.source_filename}"
        return hashlib.md5(task_string.encode()).hexdigest()[:12]


class CheckpointManager:
    """Manages recording session checkpoints"""

    def __init__(self, checkpoint_file: str):
        self.checkpoint_file = Path(checkpoint_file)
        self.tasks: Dict[str, RecordingTask] = {}
        self.session_metadata = {
            'created': datetime.now().isoformat(),
            'last_updated': None,
            'session_type': 'recording',
            'version': '2.0'
        }

        # Ensure checkpoint directory exists
        self.checkpoint_file.parent.mkdir(parents=True, exist_ok=True)

        # Load existing checkpoint if available
        self.load_checkpoint()

    def load_checkpoint(self) -> bool:
        """Load existing checkpoint file"""
        if not self.checkpoint_file.exists():
            return False

        try:
            with open(self.checkpoint_file, 'r') as f:
                data = json.load(f)

            # Load metadata
            self.session_metadata.update(data.get('metadata', {}))

            # Load tasks
            for task_data in data.get('tasks', []):
                task = RecordingTask(
                    speaker=task_data['speaker'],
                    mode_name=task_data['mode_name'],
                    source_filename=task_data['source_filename'],
                    output_path=task_data['output_path'],
                    status=TaskStatus(task_data['status']),
                    timestamp=task_data.get('timestamp'),
                    error_message=task_data.get('error_message'),
                    validation_result=task_data.get('validation_result')
                )
                self.tasks[task.task_id] = task

            return True

        except (json.JSONDecodeError, KeyError, ValueError) as e:
            print(f"Warning: Could not load checkpoint file: {e}", file=sys.stderr)
            return False

    def save_checkpoint(self) -> bool:
        """Save current state to checkpoint file"""
        try:
            # Update metadata
            self.session_metadata['last_updated'] = datetime.now().isoformat()

            # Prepare data structure
            data = {
                'metadata': self.session_metadata,
                'tasks': [asdict(task) for task in self.tasks.values()]
            }

            # Convert enum values to strings
            for task_data in data['tasks']:
                task_data['status'] = task_data['status'].value

            # Write to file with atomic operation (write to temp, then rename)
            temp_file = self.checkpoint_file.with_suffix('.tmp')
            with open(temp_file, 'w') as f:
                json.dump(data, f, indent=2)

            # Atomic rename
            temp_file.replace(self.checkpoint_file)
            return True

        except Exception as e:
            print(f"Error saving checkpoint: {e}", file=sys.stderr)
            return False

    def register_task(self, speaker: str, mode_name: str, source_filename: str, output_path: str) -> str:
        """Register a new recording task"""
        task = RecordingTask(
            speaker=speaker,
            mode_name=mode_name,
            source_filename=source_filename,
            output_path=output_path
        )

        self.tasks[task.task_id] = task
        self.save_checkpoint()
        return task.task_id

    def update_task_status(self, task_id: str, status: TaskStatus,
                           error_message: str = None, validation_result: Dict = None) -> bool:
        """Update task status"""
        if task_id not in self.tasks:
            return False

        task = self.tasks[task_id]
        task.status = status
        task.timestamp = datetime.now().isoformat()

        if error_message:
            task.error_message = error_message
        if validation_result:
            task.validation_result = validation_result

        self.save_checkpoint()
        return True

    def is_task_completed(self, speaker: str, mode_name: str, source_filename: str) -> bool:
        """Check if a specific task is completed"""
        task_string = f"{speaker}|{mode_name}|{source_filename}"
        task_id = hashlib.md5(task_string.encode()).hexdigest()[:12]

        if task_id in self.tasks:
            return self.tasks[task_id].status == TaskStatus.COMPLETED
        return False

    def get_task_by_params(self, speaker: str, mode_name: str, source_filename: str) -> Optional[RecordingTask]:
        """Get task by parameters"""
        task_string = f"{speaker}|{mode_name}|{source_filename}"
        task_id = hashlib.md5(task_string.encode()).hexdigest()[:12]
        return self.tasks.get(task_id)

    def get_summary(self) -> Dict:
        """Get session summary statistics"""
        status_counts = {}
        for status in TaskStatus:
            status_counts[status.value] = 0

        for task in self.tasks.values():
            status_counts[task.status.value] += 1

        total_tasks = len(self.tasks)
        completion_rate = (status_counts[TaskStatus.COMPLETED.value] / total_tasks * 100) if total_tasks > 0 else 0

        return {
            'total_tasks': total_tasks,
            'status_counts': status_counts,
            'completion_rate': completion_rate,
            'session_created': self.session_metadata.get('created'),
            'last_updated': self.session_metadata.get('last_updated')
        }

    def get_failed_tasks(self) -> List[RecordingTask]:
        """Get all failed tasks for retry"""
        return [task for task in self.tasks.values() if task.status == TaskStatus.FAILED]

    def reset_failed_tasks(self) -> int:
        """Reset failed tasks to pending for retry"""
        reset_count = 0
        for task in self.tasks.values():
            if task.status == TaskStatus.FAILED:
                task.status = TaskStatus.PENDING
                task.error_message = None
                reset_count += 1

        if reset_count > 0:
            self.save_checkpoint()
        return reset_count

    def export_legacy_format(self, legacy_file: str) -> bool:
        """Export checkpoint data in legacy text format for bash compatibility"""
        try:
            with open(legacy_file, 'w') as f:
                f.write("# Recording Progress Checkpoint File\n")
                f.write(f"# Generated on {datetime.now()}\n")
                f.write("# Format: speaker|mode_name|source_filename|output_path|status|timestamp\n")

                for task in self.tasks.values():
                    f.write(
                        f"{task.speaker}|{task.mode_name}|{task.source_filename}|{task.output_path}|{task.status.value}|{task.timestamp}\n")

            return True
        except Exception as e:
            print(f"Error exporting legacy format: {e}", file=sys.stderr)
            return False


def main():
    """Command line interface for checkpoint management"""
    if len(sys.argv) < 3:
        print("Usage: python3 checkpoint_manager.py <command> <checkpoint_file> [args...]")
        print("Commands:")
        print("  init <checkpoint_file>                                   - Initialize new checkpoint")
        print("  is_completed <checkpoint_file> <speaker> <mode> <file>   - Check if task is completed")
        print("  register <checkpoint_file> <speaker> <mode> <file> <output> - Register new task")
        print("  complete <checkpoint_file> <task_id>                     - Mark task as completed")
        print("  fail <checkpoint_file> <task_id> <error_message>         - Mark task as failed")
        print("  summary <checkpoint_file>                                - Show session summary")
        print("  export_legacy <checkpoint_file> <legacy_file>            - Export to legacy format")
        sys.exit(1)

    command = sys.argv[1]
    checkpoint_file = sys.argv[2]

    manager = CheckpointManager(checkpoint_file)

    if command == "init":
        manager.save_checkpoint()
        print("Checkpoint initialized")

    elif command == "is_completed":
        if len(sys.argv) != 6:
            print("Usage: is_completed <checkpoint_file> <speaker> <mode> <source_file>")
            sys.exit(1)

        speaker, mode, source_file = sys.argv[3:6]
        is_completed = manager.is_task_completed(speaker, mode, source_file)
        print("true" if is_completed else "false")
        sys.exit(0 if is_completed else 1)

    elif command == "register":
        if len(sys.argv) != 7:
            print("Usage: register <checkpoint_file> <speaker> <mode> <source_file> <output_path>")
            sys.exit(1)

        speaker, mode, source_file, output_path = sys.argv[3:7]
        task_id = manager.register_task(speaker, mode, source_file, output_path)
        print(task_id)

    elif command == "complete":
        if len(sys.argv) != 4:
            print("Usage: complete <checkpoint_file> <task_id>")
            sys.exit(1)

        task_id = sys.argv[3]
        success = manager.update_task_status(task_id, TaskStatus.COMPLETED)
        sys.exit(0 if success else 1)

    elif command == "fail":
        if len(sys.argv) < 4:
            print("Usage: fail <checkpoint_file> <task_id> [error_message]")
            sys.exit(1)

        task_id = sys.argv[3]
        error_message = sys.argv[4] if len(sys.argv) > 4 else "Unknown error"
        success = manager.update_task_status(task_id, TaskStatus.FAILED, error_message=error_message)
        sys.exit(0 if success else 1)

    elif command == "summary":
        summary = manager.get_summary()
        print(json.dumps(summary, indent=2))

    elif command == "export_legacy":
        if len(sys.argv) != 4:
            print("Usage: export_legacy <checkpoint_file> <legacy_file>")
            sys.exit(1)

        legacy_file = sys.argv[3]
        success = manager.export_legacy_format(legacy_file)
        sys.exit(0 if success else 1)

    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == "__main__":
    main()