# Process Killing Fix

## Problem
Processes were not actually being killed when sending signals (SIGTERM, SIGKILL, etc.) through the SSH connection.

## Root Cause
The `SSHClient.execute()` method returns a `SSHSession` that needs to have its output streams consumed and exit code awaited for the command to actually complete. Simply calling `execute()` without reading the output doesn't guarantee the command finishes.

## Original Code
```dart
await widget.sshClient!.execute(command);
```

This would start the command but not wait for it to complete properly.

## Fixed Code
```dart
// Execute the command and wait for completion
final session = await widget.sshClient!.execute(command);

// Read the output to ensure command completes
await utf8.decodeStream(session.stdout); // Consume stdout
final stderr = await utf8.decodeStream(session.stderr);

// Wait for exit code
final exitCode = await session.exitCode;

if (mounted) {
  if (exitCode == 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$signalName sent to PID $pid'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  } else {
    // Show error if command failed
    final errorMsg = stderr.isNotEmpty ? stderr.trim() : 'Command failed with exit code $exitCode';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Failed to send $signalName to PID $pid: $errorMsg'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
```

## What Changed

### 1. Stream Consumption
- **stdout**: Consumed to ensure command processes
- **stderr**: Read to capture any error messages

### 2. Exit Code Check
- Wait for `session.exitCode` to complete
- Check if `exitCode == 0` for success
- Show appropriate success/error message

### 3. Better Error Reporting
- If command fails (exitCode != 0), show the actual error from stderr
- If stderr is empty, show exit code
- Helps debug permission issues or invalid PIDs

### 4. Proper Timing
- Snackbar durations adjusted (2s success, 3s error)
- Still refresh process list after 500ms delay
- Added mounted check before refresh

## Benefits

1. **Commands Actually Execute**: Streams are consumed so SSH command completes
2. **Success Verification**: Exit code confirms command succeeded
3. **Error Details**: User sees actual error messages (e.g., "Operation not permitted")
4. **Permission Issues**: Clear feedback when lacking sudo/root access
5. **Invalid PID**: Shows error if PID doesn't exist

## Example Error Messages

### Success
```
✓ SIGKILL sent to PID 1234
```

### Permission Denied
```
✗ Failed to send SIGKILL to PID 1234: Operation not permitted
```

### Invalid PID
```
✗ Failed to send SIGKILL to PID 9999: No such process
```

### SSH Error
```
✗ Failed to send SIGKILL to PID 1234: Connection lost
```

## Testing

To test the fix:

1. **Kill Normal Process**
   - Find a user-owned process
   - Send SIGKILL
   - Should succeed and process disappears

2. **Kill System Process (Without Root)**
   - Try to kill a root-owned process
   - Should show "Operation not permitted" error
   - Process remains in list

3. **Kill Invalid PID**
   - Try to kill PID 99999
   - Should show "No such process" error

4. **Pause/Resume Process**
   - Send SIGSTOP to pause
   - Process state changes to T
   - Send SIGCONT to resume
   - Process state changes back

5. **Terminate Gracefully**
   - Send SIGTERM to an application
   - Application should exit gracefully
   - Process disappears after cleanup

## SSH Command Flow

```
User taps Kill
    ↓
Confirmation dialog
    ↓
User confirms
    ↓
SSH: kill -9 1234
    ↓
Read stdout (empty)
    ↓
Read stderr (errors if any)
    ↓
Wait for exit code
    ↓
exitCode == 0?
    ↓
Yes: Show success snackbar
No: Show error with stderr
    ↓
Refresh process list
    ↓
Process removed (if successful)
```

## Additional Notes

### Why This Matters
SSH commands are asynchronous operations. Without consuming the output streams and waiting for the exit code, the Dart code continues immediately without ensuring the remote command completed. This is especially important for `kill` commands where we need to verify the signal was actually sent.

### Alternative Approaches Considered

1. **Fire and Forget**: Just execute and assume success
   - ❌ No error feedback
   - ❌ Can't verify completion

2. **Only Check Exit Code**: Skip reading streams
   - ❌ Streams must be consumed for SSH2 library
   - ❌ Command may hang

3. **Current Solution**: Read streams + check exit code
   - ✅ Verifies completion
   - ✅ Provides error details
   - ✅ Works reliably

### Performance Impact
- Minimal: Reading empty stdout/stderr is very fast
- Exit code check: Milliseconds
- Overall: No noticeable delay for users

## Related Files
- `lib/screens/device_processes_screen.dart` - Main fix location

## Future Enhancements
1. **Sudo Support**: Option to execute with sudo for system processes
2. **Batch Operations**: Select multiple processes to kill at once
3. **Signal History**: Log of signals sent and results
4. **Custom Signals**: Allow sending any signal number
5. **Process Tree Kill**: Kill process and all children
