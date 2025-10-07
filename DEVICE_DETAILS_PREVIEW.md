# Device Details Screen - Visual Preview

## Screen Layout

```
┌─────────────────────────────────────────────────┐
│  ← Device Details              🔄 Refresh        │
├─────────────────────────────────────────────────┤
│                                                  │
│  ┌───────────────┐  ┌───────────────┐          │
│  │  📊 CPU       │  │  💾 RAM       │          │
│  │               │  │               │          │
│  │     75.2%     │  │     62.8%     │          │
│  │   ●●●●●○○○    │  │   ●●●●●●○○    │          │
│  └───────────────┘  └───────────────┘          │
│                                                  │
│  ┌───────────────┐  ┌───────────────┐          │
│  │  💽 Storage   │  │  ⏱️ Uptime     │          │
│  │               │  │               │          │
│  │     45.3%     │  │  2d 14h 32m   │          │
│  │   ●●●●○○○○    │  │               │          │
│  └───────────────┘  └───────────────┘          │
│                                                  │
├─────────────────────────────────────────────────┤
│                                                  │
│  ┌──────────────────┐  ┌─────────────────────┐ │
│  │ 📊 Load Avg      │  │ 📱 Processes        │ │
│  │ 0.45/0.52/0.48   │  │ 287                 │ │
│  └──────────────────┘  └─────────────────────┘ │
│                                                  │
│  ┌──────────────────┐  ┌─────────────────────┐ │
│  │ 🌡️ Temp          │  │ 🌐 Hostname         │ │
│  │ 52.3°C           │  │ ubuntu-server       │ │
│  └──────────────────┘  └─────────────────────┘ │
│                                                  │
├─────────────────────────────────────────────────┤
│                                                  │
│  Memory Breakdown                                │
│  ┌──────────────────────────────────────────┐  │
│  │  ● Total       8.00 GB                   │  │
│  │  ● Used        5.12 GB                   │  │
│  │  ● Free        1.23 GB                   │  │
│  │  ● Available   2.88 GB                   │  │
│  │  ● Cached      1.89 GB                   │  │
│  │  ● Buffers     0.54 GB                   │  │
│  │  ──────────────────────────────────      │  │
│  │  ● Swap Total  4.00 GB                   │  │
│  │  ● Swap Used   0.25 GB                   │  │
│  │                                           │  │
│  │  ▓▓░░░░░░░░░░░░░░ Swap Usage: 6.3%       │  │
│  └──────────────────────────────────────────┘  │
│                                                  │
├─────────────────────────────────────────────────┤
│                                                  │
│  I/O Statistics                                  │
│  ┌──────────────────────────────────────────┐  │
│  │  💾 Disk I/O                             │  │
│  │  125.3 kB/s read, 89.7 kB/s write        │  │
│  └──────────────────────────────────────────┘  │
│                                                  │
│  ┌──────────────────────────────────────────┐  │
│  │  ⬍ Network Traffic                       │  │
│  │  ↓ 2847.3 MB ↑ 1253.8 MB                 │  │
│  └──────────────────────────────────────────┘  │
│                                                  │
├─────────────────────────────────────────────────┤
│                                                  │
│  System Information                              │
│  ┌──────────────────────────────────────────┐  │
│  │  💻 OS                                    │  │
│  │  Ubuntu 22.04.3 LTS                      │  │
│  └──────────────────────────────────────────┘  │
│                                                  │
│  ┌──────────────────────────────────────────┐  │
│  │  ⚙️ Kernel                                │  │
│  │  5.15.0-89-generic                       │  │
│  └──────────────────────────────────────────┘  │
│                                                  │
│  ┌──────────────────────────────────────────┐  │
│  │  🌐 Network                               │  │
│  │  192.168.1.150                           │  │
│  └──────────────────────────────────────────┘  │
│                                                  │
│  ┌──────────────────────────────────────────┐  │
│  │  🔋 Battery                               │  │
│  │  Not available                           │  │
│  └──────────────────────────────────────────┘  │
│                                                  │
├─────────────────────────────────────────────────┤
│                                                  │
│  Top Processes                                   │
│  ┌──────────────────────────────────────────┐  │
│  │  🔵 1234  /usr/bin/chrome    CPU: 15.3%  │  │
│  │                              MEM: 8.2%   │  │
│  └──────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────┐  │
│  │  🔵 5678  /usr/lib/firefox   CPU: 12.1%  │  │
│  │                              MEM: 6.7%   │  │
│  └──────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────┐  │
│  │  🔵 9012  /opt/code/code     CPU: 8.9%   │  │
│  │                              MEM: 5.4%   │  │
│  └──────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────┐  │
│  │  🔵 3456  /usr/bin/python3   CPU: 7.2%   │  │
│  │                              MEM: 3.8%   │  │
│  └──────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────┐  │
│  │  🔵 7890  /usr/sbin/mysql    CPU: 5.6%   │  │
│  │                              MEM: 4.1%   │  │
│  └──────────────────────────────────────────┘  │
│                                                  │
└─────────────────────────────────────────────────┘
```

## Feature Highlights

### 🎯 Quick Stats (Top Section)
Four circular gauges showing real-time metrics with animated radial progress indicators:
- CPU usage percentage
- RAM usage percentage
- Storage usage percentage
- System uptime in days/hours/minutes

### 📊 System Stats Cards
Compact info cards displaying:
- **Load Average**: System load over 1, 5, and 15 minutes
- **Process Count**: Total number of running processes
- **Temperature**: CPU temperature with color warning (red >75°C)
- **Hostname**: Device network hostname

### 💾 Memory Deep Dive
Comprehensive memory breakdown card with:
- 6 main memory metrics (Total, Used, Free, Available, Cached, Buffers)
- Color-coded circular indicators
- Precise GB measurements
- Optional swap statistics with progress bar
- Visual swap usage percentage

### 📈 I/O Monitoring
Real-time performance metrics:
- **Disk I/O**: Read/write speeds in kB/s
- **Network Traffic**: Total download/upload since boot

### ℹ️ System Details
Essential system information:
- Operating system name and version
- Linux kernel version
- Network IP address configuration
- Battery status (for portable devices)

### 🔝 Process Monitor
Live process list showing:
- Process ID (PID) in colored badge
- Command/executable path
- CPU usage percentage
- Memory usage percentage
- Sorted by CPU usage (highest first)

## Color Coding System

| Element          | Color       | Meaning                    |
|------------------|-------------|----------------------------|
| CPU Gauge        | Blue        | Processing power           |
| RAM Gauge        | Purple      | Memory usage               |
| Storage Gauge    | Orange      | Disk utilization           |
| Uptime Card      | Green       | Stability indicator        |
| Load Average     | Cyan        | System load                |
| Processes        | Deep Purple | Active tasks               |
| Temperature      | Orange/Red  | Heat level (red = warning) |
| Hostname         | Blue Grey   | Network identity           |
| Disk I/O         | Brown       | Storage performance        |
| Network Traffic  | Green       | Network activity           |
| Kernel Info      | Deep Orange | Core system                |

## Interaction Features

### 🔄 Auto-Refresh
- Automatically updates every 5 seconds
- Shows real-time changes in all metrics
- Timer-based background updates

### ⬇️ Pull-to-Refresh
- Swipe down to force immediate update
- Loading indicator during fetch
- Instant data synchronization

### 🔁 Manual Refresh
- Tap refresh button in app bar
- Immediately fetches latest data
- Useful for verification

### ⚡ Error Handling
- Graceful fallbacks for missing commands
- Clear error messages for connection issues
- Retry button on SSH failures

## Data Update Frequency

| Metric           | Update Method | Frequency    |
|------------------|---------------|--------------|
| CPU Usage        | Auto          | 5 seconds    |
| RAM Usage        | Auto          | 5 seconds    |
| Storage          | Auto          | 5 seconds    |
| Temperature      | Auto          | 5 seconds    |
| Load Average     | Auto          | 5 seconds    |
| Process Count    | Auto          | 5 seconds    |
| Disk I/O         | Auto          | 5 seconds    |
| Network Traffic  | Auto          | 5 seconds    |
| Memory Details   | Auto          | 5 seconds    |
| Top Processes    | Auto          | 5 seconds    |
| OS/Kernel/Host   | Once          | On load only |

## Responsive Design

- Scrollable layout for all content
- Two-column grid for stat cards
- Full-width cards for detailed info
- Compact process list with dense tiles
- Adaptive gauge sizing
- Proper padding and spacing
- Material Design 3 elevation

## Performance Characteristics

- **16 concurrent SSH commands** executed in parallel
- **~3-5 seconds** total fetch time (network dependent)
- **Minimal memory footprint** with efficient state management
- **Smooth animations** on gauge updates
- **No UI blocking** during data refresh
- **Automatic cleanup** when screen unmounted

## Accessibility

- Clear icon representations
- Color-independent information (text always present)
- Readable font sizes
- Proper contrast ratios
- Descriptive labels
- Logical reading order
