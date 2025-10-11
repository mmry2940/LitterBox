# Device Processes Screen Enhancements

## Overview
The Device Processes Screen has been completely redesigned with advanced process management capabilities, better UI/UX, and comprehensive filtering and sorting options.

## 🎯 Key Improvements

### 1. **Fixed Auto-Refresh Implementation**
**Before**: Used a `while` loop which could cause issues
```dart
void _startAutoRefresh() async {
  while (_autoRefresh && mounted) {
    await _fetchProcesses();
    await Future.delayed(const Duration(seconds: 5));
  }
}
```

**After**: Uses proper `Timer` with cleanup
```dart
void _startAutoRefresh() {
  _autoRefreshTimer?.cancel();
  _autoRefreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
    if (mounted) {
      _fetchProcesses();
    } else {
      timer.cancel();
    }
  });
}
```

### 2. **Summary Dashboard**
Added real-time metrics at the top:
- **Total Processes**: Count of all running processes
- **Showing**: Number of filtered/visible processes
- **Total CPU Usage**: Aggregate CPU usage across all processes
- **Total Memory Usage**: Aggregate memory usage across all processes

Each metric is color-coded:
- Red: High usage (>80%)
- Green: Normal usage

### 3. **Enhanced Search**
- Clear button appears when text is entered
- Real-time filtering as you type
- Searches across all process fields (PID, USER, COMMAND, etc.)
- Visual feedback when no results found

### 4. **Process State Filtering**
Added filter chips for process states:
- **All**: Show all processes
- **Running**: Processes in R state
- **Sleeping**: Processes in S or I state
- **Stopped**: Processes in T state
- **Zombie**: Processes in Z state

Color-coded stat chips in process list:
- Green: Running (R)
- Blue: Sleeping (S/I)
- Orange: Stopped (T)
- Red: Zombie (Z)

### 5. **Advanced Sorting**
Interactive sort chips with visual indicators:
- **CPU**: Sort by CPU usage (default descending)
- **MEM**: Sort by memory usage (default descending)
- **PID**: Sort by process ID
- **User**: Sort by username

Features:
- Arrow indicator shows sort direction (↑↓)
- Click same chip to toggle direction
- Ascending/descending based on data type

### 6. **Multiple Process Signals**
Replaced simple "Kill" with full signal menu:

| Signal    | Icon  | Color  | Description                    | Command         |
|-----------|-------|--------|--------------------------------|-----------------|
| SIGTERM   | Stop  | Orange | Gracefully terminate process   | `kill PID`      |
| SIGKILL   | Cancel| Red    | Force kill immediately         | `kill -9 PID`   |
| SIGSTOP   | Pause | Blue   | Suspend process execution      | `kill -STOP PID`|
| SIGCONT   | Play  | Green  | Resume suspended process       | `kill -CONT PID`|

### 7. **Enhanced Process Details Sheet**
Complete redesign with:

#### Visual Metrics (4 Cards)
- **PID**: Process identifier with tag icon
- **USER**: Process owner with person icon  
- **CPU**: Usage percentage (color-coded)
- **MEM**: Memory percentage (color-coded)

#### Detailed Information
- Status (STAT)
- Terminal (TTY)
- Start Time
- CPU Time consumed
- Virtual memory size (VSZ)
- Resident set size (RSS)

#### Quick Actions
Four prominent buttons for process control:
- **Terminate**: Send SIGTERM (orange)
- **Kill**: Send SIGKILL (red)
- **Pause**: Send SIGSTOP (blue)
- **Continue**: Send SIGCONT (green)

### 8. **Color-Coded Performance Indicators**

#### Process Cards
- **High Usage Border**: Red border on cards with CPU or MEM >50%
- **Elevated Shadow**: Cards with high usage have increased elevation
- **PID Badge Color**: Red background for high CPU, blue for normal

#### CPU/MEM Chips
- **Red**: >50% usage
- **Orange**: 20-50% usage
- **Green**: <20% usage

### 9. **Pull-to-Refresh**
Swipe down gesture to manually refresh process list with visual indicator.

### 10. **Better Error Handling**
Enhanced error states with:
- Error icon (64px)
- Clear error message
- Retry button
- Proper SSH error handling
- Permission denied feedback
- Signal send error messages

### 11. **Improved Visual Hierarchy**

#### Process List Item Structure
```
┌─────────────────────────────────────────┐
│ [PID] Process Command Name     [⋮ Menu] │
│                                          │
│ [CPU: X%] [MEM: Y%] [USER] [STAT]      │
└─────────────────────────────────────────┘
```

#### Empty States
- No SSH: Cloud icon + message
- No processes: Hourglass + Load button
- No search results: Search off icon + Clear button

## 🎨 UI Components

### Summary Cards
```dart
_buildSummaryCard(label, value, icon, color)
```
- Compact design for dashboard metrics
- Icon + Value + Label layout
- Color-coded border and background

### Process Info Chips
```dart
ProcessInfoChip(label, value, color)
```
- Auto color-coding for CPU/MEM
- Border for visual separation
- Compact padding

### Process Detail Sheet
```dart
ProcessDetailSheet(proc, onSignal)
```
- Full-width bottom sheet
- Metric cards in 2x2 grid
- Action buttons in wrap layout
- Scrollable content

## 📊 Performance Optimizations

### Filtering Logic
```dart
void _applyFilterSort() {
  // 1. State filter (if not "All")
  // 2. Search filter (if text entered)
  // 3. Sorting (numeric or string)
}
```

### Efficient Updates
- Single `setState()` call per operation
- Filtered list separate from source
- No rebuilds on scroll

### Memory Management
- Timer properly disposed
- Controllers cleaned up
- Mounted checks before updates

## 🔧 Technical Changes

### State Variables
```dart
String _sortColumn = '%CPU';           // Default sort by CPU
bool _sortAsc = false;                 // Descending by default
String _stateFilter = 'All';           // No filter initially
Timer? _autoRefreshTimer;              // Proper timer management
```

### New Methods

#### Signal Management
```dart
_onSendSignal(process, signal)  // Unified signal sender
```

#### Sorting
```dart
_changeSortColumn(column)       // Interactive sort control
```

#### Filtering  
```dart
_changeStateFilter(filter)      // State-based filtering
```

#### Statistics
```dart
_getTotalCPU()                  // Aggregate CPU usage
_getTotalMEM()                  // Aggregate memory usage
```

#### UI Helpers
```dart
_buildSummaryCard()             // Metric cards
_getStatColor()                 // State color mapping
```

## 🎭 User Experience Improvements

### Visual Feedback
1. **Active Auto-Refresh**: Orange pause icon
2. **Inactive Auto-Refresh**: Blue play icon
3. **High Resource Processes**: Red border highlight
4. **Selected Filters**: Blue chip background
5. **Selected Sort**: Green chip with arrow
6. **Signal Sent**: Green snackbar
7. **Signal Failed**: Red snackbar

### Interaction Flow
```
Launch Screen
    ↓
Load Processes (SSH)
    ↓
View Summary Dashboard
    ↓
[Optional] Apply Filters/Sort
    ↓
[Optional] Search Processes
    ↓
Tap Process → View Details
    ↓
Select Action → Confirm → Execute
    ↓
Auto-Refresh or Manual Refresh
```

### Accessibility
- Tooltips on all icon buttons
- High contrast color schemes
- Clear visual hierarchy
- Readable font sizes
- Icon + text labels

## 📱 Responsive Design

### Layout Breakpoints
- **Summary Cards**: 4 columns in row
- **Filter Chips**: Horizontal scroll
- **Sort Chips**: Horizontal scroll
- **Process List**: Full width cards

### Scroll Behavior
- Header stays fixed
- Filters/sort scroll with content
- Process list scrolls independently
- Pull-to-refresh on list only

## 🐛 Bug Fixes

### 1. **Auto-Refresh Memory Leak**
**Issue**: While loop could continue after widget disposed
**Fix**: Timer with mounted checks

### 2. **Sorting Not Functional**
**Issue**: Sort variables declared but never used
**Fix**: Added interactive sort chips with `_changeSortColumn()`

### 3. **No Visual Sort Feedback**
**Issue**: Users couldn't tell current sort state
**Fix**: Added selected chip color and arrow indicators

### 4. **Kill Permission Errors**
**Issue**: No feedback when kill command fails
**Fix**: Try-catch with error snackbar

### 5. **Process State Ignored**
**Issue**: No way to filter by process state
**Fix**: Added state filter chips

### 6. **Missing Clear Search**
**Issue**: Had to delete text manually
**Fix**: Added X button in search field

## 🚀 New Features

### 1. Process Highlighting
- Automatic red border on high-usage processes
- Makes resource hogs immediately visible
- Helps identify performance issues

### 2. State-Based Filtering
- Filter by Running, Sleeping, Stopped, Zombie
- Colored stat chips for quick identification
- Useful for troubleshooting

### 3. Multi-Signal Support
- SIGTERM for graceful shutdown
- SIGKILL for forced termination
- SIGSTOP to pause debugging
- SIGCONT to resume execution

### 4. Statistics Dashboard
- See total system load at a glance
- Monitor aggregate resource usage
- Track filtered vs total processes

### 5. Enhanced Details View
- Professional metric cards
- All process info in one place
- Quick actions without closing sheet

## 💡 Usage Tips

### Finding Resource Hogs
1. Sort by CPU or MEM (descending)
2. Look for red-bordered cards
3. Tap for details

### Monitoring Specific User
1. Enter username in search
2. Or use USER sort chip
3. View all user's processes

### Managing Background Tasks
1. Filter by "Sleeping"
2. Find unwanted services
3. Terminate or kill

### Debugging Applications
1. Search for app name
2. View process details
3. Use SIGSTOP to pause
4. Investigate issue
5. Use SIGCONT to resume

### Finding Zombie Processes
1. Filter by "Zombie"
2. Kill parent process
3. Or manually terminate

## 🔮 Future Enhancement Ideas

1. **Process Tree View**: Show parent-child relationships
2. **Resource Graphs**: Historical CPU/MEM charts
3. **Process Groups**: Group by user or application
4. **Custom Signals**: Advanced users can send any signal
5. **Process Priority**: Change nice values
6. **CPU Affinity**: Pin processes to cores
7. **Memory Details**: Detailed memory breakdown per process
8. **Open Files**: Show files opened by process
9. **Network Connections**: Show active connections
10. **Process Export**: Export process list to CSV
11. **Alerts**: Notify on high CPU/MEM
12. **Comparison**: Compare before/after snapshots

## 📏 Code Metrics

### Lines of Code
- **Before**: ~250 lines
- **After**: ~780 lines
- **Increase**: +530 lines (+212%)

### Features
- **Before**: 4 features
- **After**: 15 features
- **Increase**: +11 features (+275%)

### Methods
- **Before**: 8 methods
- **After**: 18 methods
- **Increase**: +10 methods (+125%)

### User Actions
- **Before**: 3 actions (search, kill, refresh)
- **After**: 10+ actions (search, clear, filter, sort, signals, pull-refresh, auto-refresh, etc.)

## 🎓 Learning Points

### Flutter Best Practices Used
1. **Timer Management**: Proper disposal prevents memory leaks
2. **Pull-to-Refresh**: Standard mobile gesture
3. **Chips for Filters**: Material Design pattern
4. **Snackbar Feedback**: Non-intrusive notifications
5. **Bottom Sheets**: Contextual detail views
6. **Color Coding**: Visual hierarchy and meaning
7. **Empty States**: Helpful placeholder content
8. **Error States**: Actionable error recovery

### SSH Command Techniques
1. **SIGTERM vs SIGKILL**: Graceful vs forced termination
2. **Process States**: Understanding STAT column
3. **Signal Numbers**: kill -9, kill -STOP, etc.
4. **Process Attributes**: VSZ, RSS, %CPU, %MEM meaning
5. **ps aux Format**: Parsing Unix process output

## 📝 Migration Notes

### Breaking Changes
None - All changes are enhancements

### Deprecated Features
- `_onKill()` method replaced with `_onSendSignal()`
- Old auto-refresh loop replaced with Timer

### Backward Compatibility
Fully compatible with existing SSHClient interface

## 🔍 Testing Checklist

- [ ] Auto-refresh starts and stops correctly
- [ ] Timer disposed on screen exit
- [ ] All filter chips work
- [ ] All sort options work
- [ ] Sort direction toggles
- [ ] Search filters results
- [ ] Clear search button works
- [ ] Pull-to-refresh triggers update
- [ ] SIGTERM sends correctly
- [ ] SIGKILL sends correctly
- [ ] SIGSTOP sends correctly
- [ ] SIGCONT sends correctly
- [ ] Signal confirmation dialogs appear
- [ ] Error messages shown on failure
- [ ] Success messages shown on success
- [ ] Process details sheet opens
- [ ] All metrics display correctly
- [ ] High-usage processes highlighted
- [ ] Summary cards show correct totals
- [ ] State colors match process states
- [ ] Empty states display properly
- [ ] Error states display properly

## 📄 File Location

`lib/screens/device_processes_screen.dart`

## 🎉 Result

A professional, feature-rich process manager that rivals dedicated system monitoring applications. Users can now effectively monitor, filter, sort, and control processes with an intuitive, modern interface.
