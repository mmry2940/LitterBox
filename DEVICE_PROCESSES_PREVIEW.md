# Device Processes Screen - Visual Preview

## Enhanced Screen Layout

```
┌─────────────────────────────────────────────────────────────┐
│  ← Device Processes                                          │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐│
││  SUMMARY DASHBOARD                                          ││
││  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐     ││
││  │ 📱 Apps  │ │ 📋 Show  │ │ 💻 CPU   │ │ 💾 MEM   │     ││
││  │   287    │ │    45    │ │  75.2%   │ │  62.8%   │     ││
││  │  Total   │ │ Showing  │ │   CPU    │ │   MEM    │     ││
││  └──────────┘ └──────────┘ └──────────┘ └──────────┘     ││
│  └─────────────────────────────────────────────────────────┘│
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐│
││  CONTROLS                                                   ││
││  ┌─────────────────────────────────┐  [⏸]  [🔄]          ││
││  │ 🔍 Search processes...       [✕]│                       ││
││  └─────────────────────────────────┘                       ││
││                                                             ││
││  Filter: [All] [Running] [Sleeping] [Stopped] [Zombie]    ││
││                                                             ││
││  Sort: [CPU ↓] [MEM] [PID] [User]                         ││
│  └─────────────────────────────────────────────────────────┘│
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐│
││  PROCESS LIST                                               ││
││                                                             ││
││  ┌───────────────────────────────────────────────────────┐ ││
││  │ [1234] /usr/bin/chrome                            [⋮] │ ││
││  │                                                        │ ││
││  │ [CPU: 15.3%] [MEM: 8.2%] [USER: root] [STAT: R]     │ ││
││  └───────────────────────────────────────────────────────┘ ││
││                                                             ││
││  ┌───────────────────────────────────────────────────────┐ ││
││  │ [5678] /usr/lib/firefox                           [⋮] │ ││
││  │                                                        │ ││
││  │ [CPU: 12.1%] [MEM: 6.7%] [USER: john] [STAT: S]     │ ││
││  └───────────────────────────────────────────────────────┘ ││
││                                                             ││
││  ┌───────────────────────────────────────────────────────┐ ││
││  │ [9012] /opt/code/code                             [⋮] │ ││
││  │                                                        │ ││
││  │ [CPU: 8.9%] [MEM: 5.4%] [USER: jane] [STAT: S]      │ ││
││  └───────────────────────────────────────────────────────┘ ││
││                                                             ││
││  ┌───────────────────────────────────────────────────────┐ ││
││  │ [3456] python3 ml_training.py                     [⋮] │ ││  
││  │ ⚠️ HIGH RESOURCE USAGE                                 │ ││
││  │ [CPU: 87.5%] [MEM: 45.8%] [USER: data] [STAT: R]    │ ││
││  └───────────────────────────────────────────────────────┘ ││
││                                                             ││
│  └─────────────────────────────────────────────────────────┘│
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

## Process Detail Sheet

```
┌─────────────────────────────────────────────────────────────┐
│  🖥️  /usr/bin/chrome --type=renderer                         │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌─────────────────┐     ┌─────────────────┐               │
│  │   🏷️ PID        │     │   👤 USER        │               │
│  │                 │     │                 │               │
│  │     1234        │     │     root        │               │
│  └─────────────────┘     └─────────────────┘               │
│                                                               │
│  ┌─────────────────┐     ┌─────────────────┐               │
│  │   💻 CPU        │     │   💾 MEM        │               │
│  │                 │     │                 │               │
│  │    15.3%        │     │     8.2%        │               │
│  └─────────────────┘     └─────────────────┘               │
│                                                               │
│  Status:      R (Running)                                    │
│  TTY:         pts/0                                          │
│  Start Time:  09:45                                          │
│  CPU Time:    00:05:23                                       │
│  VSZ:         2847392                                        │
│  RSS:         645228                                         │
│                                                               │
│  ────────────────────────────────────────────────────────   │
│                                                               │
│  Process Actions                                             │
│                                                               │
│  [🛑 Terminate] [❌ Kill] [⏸️ Pause] [▶️ Continue]         │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

## Context Menu (⋮)

```
┌──────────────────────────────┐
│ 🛑 Terminate (SIGTERM)       │
├──────────────────────────────┤
│ ❌ Kill (SIGKILL)            │
├──────────────────────────────┤
│ ⏸️  Pause (SIGSTOP)           │
├──────────────────────────────┤
│ ▶️  Continue (SIGCONT)        │
└──────────────────────────────┘
```

## Signal Confirmation Dialog

```
┌─────────────────────────────────────┐
│  Send SIGKILL                       │
├─────────────────────────────────────┤
│                                     │
│  Send SIGKILL to PID 1234           │
│  (/usr/bin/chrome)?                 │
│                                     │
│           [Cancel]  [Confirm]       │
│                                     │
└─────────────────────────────────────┘
```

## Feature Highlights

### 📊 Summary Dashboard
```
┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
│ 📱       │  │ 📋       │  │ 💻       │  │ 💾       │
│  287     │  │   45     │  │  75.2%   │  │  62.8%   │
│ Total    │  │ Showing  │  │   CPU    │  │   MEM    │
└──────────┘  └──────────┘  └──────────┘  └──────────┘
```

**Live Updates Every 5 Seconds** (when auto-refresh enabled)

### 🔍 Smart Search
```
┌─────────────────────────────────────┐
│ 🔍 Search processes...           ✕  │
└─────────────────────────────────────┘
```
- Real-time filtering
- Clear button appears when typing
- Searches: PID, USER, COMMAND, STAT, etc.

### 🎯 State Filters
```
[All] [Running] [Sleeping] [Stopped] [Zombie]
 ✓
```
- **All**: 287 processes
- **Running**: 3 processes (R state)
- **Sleeping**: 276 processes (S/I state)
- **Stopped**: 0 processes (T state)
- **Zombie**: 1 process (Z state)

### 🔢 Sort Options
```
[CPU ↓] [MEM] [PID] [User]
  ✓
```
- Click to select sort column
- Arrow shows direction (↑ ascending, ↓ descending)
- Click again to toggle direction

### 🎨 Color Coding

#### CPU/MEM Chips
```
High (>50%):     [CPU: 87.5%]  ← Red background
Medium (20-50%): [MEM: 32.4%]  ← Orange background
Low (<20%):      [CPU: 5.2%]   ← Green background
```

#### Process State Chips
```
Running:  [STAT: R]  ← Green background
Sleeping: [STAT: S]  ← Blue background
Stopped:  [STAT: T]  ← Orange background
Zombie:   [STAT: Z]  ← Red background
```

#### High-Usage Highlighting
```
┌───────────────────────────────────────┐
│ [3456] python3 training.py      [⋮]  │ ← Red border
│ ⚠️ HIGH RESOURCE USAGE                 │ ← Elevated shadow
│ [CPU: 87.5%] [MEM: 45.8%] ...        │
└───────────────────────────────────────┘
```

### ⏱️ Auto-Refresh Controls
```
Active:   [⏸️ Orange pause icon]
Inactive: [▶️ Blue play icon]
Manual:   [🔄 Refresh icon]
```

### 📱 Pull-to-Refresh
```
     ↓
   ○ ○ ○  ← Loading indicator
     ↓
Swipe down to refresh
```

## Empty States

### No SSH Connection
```
        ☁️
      (64px)

Waiting for SSH connection...
```

### No Processes Loaded
```
        ⏳
      (64px)

   No processes loaded

    [Load Processes]
```

### No Search Results
```
        🔍⃠
      (64px)

   No processes found

    [Clear Search]
```

## Error States

### SSH Error
```
        ⚠️
      (64px)

SSH Error: Connection refused

      [Retry]
```

### Command Failed
```
┌─────────────────────────────────┐
│ Failed to send SIGKILL to      │
│ PID 1234: Permission denied     │
└─────────────────────────────────┘
```

## Success Feedback

### Signal Sent
```
┌─────────────────────────────────┐
│ ✓ SIGKILL sent to PID 1234      │
└─────────────────────────────────┘
Green snackbar
```

## Interaction Flows

### Flow 1: Find and Kill High CPU Process
```
1. User opens screen
   ↓
2. Sees dashboard: "CPU: 175.3%"
   ↓
3. CPU chip already selected (default sort)
   ↓
4. Sees red-bordered card at top
   ↓
5. Taps menu (⋮) → Kill
   ↓
6. Confirms in dialog
   ↓
7. Sees "SIGKILL sent to PID 3456"
   ↓
8. Process disappears from list
   ↓
9. Dashboard updates: "CPU: 87.8%"
```

### Flow 2: Monitor User's Processes
```
1. User types "john" in search
   ↓
2. List filters to show only john's processes
   ↓
3. Dashboard shows: "Showing: 12"
   ↓
4. User taps process for details
   ↓
5. Bottom sheet shows full info
   ↓
6. User closes sheet
   ↓
7. Taps [✕] to clear search
   ↓
8. Full list returns
```

### Flow 3: Pause/Resume Debugging
```
1. User searches "myapp"
   ↓
2. Finds process PID 7890
   ↓
3. Taps process card
   ↓
4. Detail sheet opens
   ↓
5. Taps [⏸️ Pause] button
   ↓
6. Confirms SIGSTOP
   ↓
7. Process state changes to T
   ↓
8. User debugs issue
   ↓
9. Opens details again
   ↓
10. Taps [▶️ Continue]
    ↓
11. Confirms SIGCONT
    ↓
12. Process resumes (state → R)
```

### Flow 4: Find Zombie Processes
```
1. User taps [Zombie] filter chip
   ↓
2. List shows only Z state processes
   ↓
3. Dashboard: "Showing: 1"
   ↓
4. User sees zombie process
   ↓
5. Taps menu → Kill
   ↓
6. Process removed
   ↓
7. Back to [All] filter
```

## Responsive Behavior

### Portrait Mode
```
┌─────────────────────┐
│  [4 summary cards]  │ ← Tight fit
│  [Search + icons]   │
│  [Filter chips]     │ ← Scroll horizontally
│  [Sort chips]       │ ← Scroll horizontally
│  ┌─────────────────┐│
│  │ Process 1       ││
│  ├─────────────────┤│
│  │ Process 2       ││
│  ├─────────────────┤│
│  │ Process 3       ││ ← Scroll vertically
│  ├─────────────────┤│
│  │ Process 4       ││
│  └─────────────────┘│
└─────────────────────┘
```

### Landscape Mode
```
┌───────────────────────────────────────┐
│  [4 summary cards wider]              │
│  [Search + icons]                     │
│  [Filter chips all visible]           │
│  [Sort chips all visible]             │
│  ┌─────────────────────────────────┐ │
│  │ Process 1                        │ │
│  ├─────────────────────────────────┤ │
│  │ Process 2                        │ │
│  ├─────────────────────────────────┤ │ ← More visible
│  │ Process 3                        │ │
│  ├─────────────────────────────────┤ │
│  │ Process 4                        │ │
│  ├─────────────────────────────────┤ │
│  │ Process 5                        │ │
│  └─────────────────────────────────┘ │
└───────────────────────────────────────┘
```

## Performance Indicators

### System Load (Normal)
```
CPU: 45.2%  ← Green
MEM: 38.7%  ← Green
```

### System Load (High)
```
CPU: 95.8%  ← Red + Bold
MEM: 87.3%  ← Red + Bold
```

### Process Card (Normal)
```
┌─────────────────────────────────┐
│ [1234] bash                 [⋮] │ ← Standard border
│ [CPU: 0.1%] [MEM: 0.3%] ...    │
└─────────────────────────────────┘
```

### Process Card (High Usage)
```
╔═════════════════════════════════╗ ← Red border (thicker)
║ [3456] python3              [⋮] ║ ← Elevated shadow
║ [CPU: 87.5%] [MEM: 45.8%] ...  ║
╚═════════════════════════════════╝
```

## Accessibility Features

### Visual Hierarchy
1. **Summary Dashboard**: Most important (top)
2. **Controls**: Frequently used (middle)
3. **Process List**: Content (scrollable)

### Icon + Text Labels
- Every action has both icon and text
- Tooltips on icon-only buttons
- Color independent information

### Touch Targets
- Minimum 48dp for all interactive elements
- Adequate spacing between chips
- Large popup menu items

### Contrast Ratios
- Black text on light backgrounds
- White text on colored buttons
- WCAG AA compliant

## Keyboard Navigation (Desktop)
```
Tab:        Navigate between controls
Enter:      Activate button/chip
Space:      Toggle chip selection
Arrows:     Navigate list
Esc:        Close bottom sheet
Ctrl+F:     Focus search (planned)
```

## Animation Timing

### Transitions
- Filter apply: 200ms
- Sort apply: 200ms
- Card highlight: 300ms
- Bottom sheet: 250ms

### Loading States
- Pull-to-refresh: Elastic bounce
- Initial load: Circular progress
- Auto-refresh: No UI interruption

## Data Update Timeline

```
T=0s:    Screen opens, load processes
T=5s:    Auto-refresh (if enabled)
T=10s:   Auto-refresh
T=15s:   Auto-refresh
...
T=Ns:    User closes screen, timer cancelled
```

## Memory Footprint

### Estimated Memory Usage
- Process list (500 procs): ~100KB
- Filtered list: ~50KB
- UI components: ~20KB
- **Total**: ~170KB (negligible)

### Optimization
- Single list copy for filtering
- No deep cloning
- Efficient setState() calls
- Timer properly disposed

## Battery Impact

### Auto-Refresh ON
- SSH command every 5s
- Minimal CPU usage
- Network bandwidth: ~5KB per request
- **Impact**: Low

### Auto-Refresh OFF
- No background activity
- **Impact**: None

## Professional Comparison

Similar to desktop tools:
- **htop**: Interactive process viewer
- **System Monitor**: GNOME system monitor
- **Task Manager**: Windows task manager

But with:
- ✅ Mobile-optimized UI
- ✅ Touch-friendly controls
- ✅ Modern Material Design
- ✅ Remote management via SSH

## Real-World Use Cases

### 1. DevOps Engineer
Monitor production servers remotely, quickly identify and terminate problematic processes.

### 2. System Administrator
Manage multiple systems, filter by user, pause/resume services.

### 3. Developer
Debug applications, pause execution, inspect process state.

### 4. IT Support
Help users identify resource-hungry applications, remote troubleshooting.

### 5. Server Management
Monitor background services, identify zombies, maintain system health.
