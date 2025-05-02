import sys
import time
import threading

class Spinner:
    """
    A text-based spinner animation for command-line interfaces.

    This class creates and manages a spinner animation that runs in a separate thread,
    allowing the main process to continue executing while providing visual feedback
    to the user that a long-running operation is in progress.

    Attributes:
        message (str): The text to display before the spinning animation.
        chars (list): Characters to use for the spinning animation.
        stop_spinning (bool): Flag to control when the spinner should stop.
        spinner_thread (Thread): The thread that runs the spinning animation.
    """

    def __init__(self, message="Working...", chars=['-', '\\', '|', '/']):
        self.message = message
        self.chars = chars
        self.stop_spinning = False
        self.spinner_thread = None

    def start(self):
        """
        Start the spinner animation in a separate thread.

        This method creates and starts a new thread that displays and updates
        the spinner animation on the console.
        """

        # Reset the stop flag in case the spinner is being reused
        self.stop_spinning = False

        # Create and configure the thread
        self.spinner_thread = threading.Thread(target=self._spin)
        self.spinner_thread.deamon = True # Thread will exit when the main program exits

        # Start the animation
        self.spinner_thread.start()

    def stop(self, completion_message=None):
        """
        Stop the spinner animation.

        This method stops the spinning animation and optionally displays a
        completion message in its place.

        Args:
            completion_message (str, optional): Message to display after stopping the spinner.
                                               If None, the line is cleared.
        """

        # Signal the spinning thread to stop
        self.stop_spinning = True

        # Wait for the thread to finish (with timeout to prevent hanging)
        if self.spinner_thread:
            self.spinner_thread.join(timeout=1)

        # Clear the spinner line and display completion message if provided
        if completion_message:
            sys.stdout.write('\r' + completion_message + ' ' * 10 + '\n')
        else:
            sys.stdout.write('\r' + ' ' * (len(self.message) + 10) + '\n')

        # Ensure the output is displayed immediately
        sys.stdout.flush()

    def _spin(self):
        """
        Internal method that runs the actual spinner animation.

        This method continuously updates the spinner character until
        the stop_spinning flag is set to True.
        """

        i = 0
        while not self.stop_spinning:
            # Write the spinner character, overwriting the previous one
            sys.stdout.write('\r' + f"{self.message} {self.chars[i % len(self.chars)]}")
            sys.stdout.flush()

            # Move to the next character in the sequence
            i += 1

            # Pause briefly to control the animation speed
            time.sleep(0.2)