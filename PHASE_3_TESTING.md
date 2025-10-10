# Phase 3 Testing Guide - Connection Wizard & Device Status

## Quick Start

### What Changed in Phase 3?
Phase 3 replaces the old cramped connection dialog with a professional **3-step wizard** and adds a background **device status monitoring service**.

**Old Way:**
- Single dialog with all fields at once
- Confusing for new users
- No guidance
- No status information

**New Way:**
- Step-by-step guided flow
- Connection type selection first
- Conditional forms based on type
- In-wizard help instructions
- Save + favorite options
- Real-time status monitoring (service ready, UI integration pending)

## How to Test

### 1. Opening the Wizard

**Steps:**
1. Run the app: `flutter run`
2. Navigate to "ADB Manager" screen
3. Click the "Dashboard" tab (should be selected by default)
4. Click the "New Connection" tab (3rd tab)
5. Click "Open Connection Wizard" button

**Expected:**
- Dialog appears (max 600x700px)
- Title "Connect to Device" with cable icon
- Stepper with 3 steps visible
- Step 1 "Connection Type" is active
- 4 connection type cards displayed

### 2. Step 1: Connection Type Selection

**Test Wi-Fi Selection:**
1. Click the "Wi-Fi" card
2. Verify border turns blue/primary color
3. Verify background tints slightly
4. Verify icon and text highlighted

**Test Each Type:**
- [ ] Wi-Fi - "Connect over wireless network"
- [ ] USB - "Connect via USB cable"
- [ ] Pairing - "Pair with code (Android 11+)"
- [ ] Custom - "Advanced connection"

**Navigation:**
- Click "Next" button → advances to Step 2
- Verify Step 1 shows checkmark
- Verify Step 2 becomes active

### 3. Step 2: Connection Details

#### Test Wi-Fi Form
**Steps:**
1. Select Wi-Fi in Step 1
2. Click Next
3. Verify fields shown:
   - Device IP Address (hint: 192.168.1.100)
   - Port (hint: 5555)
   - Help info box with setup instructions

**Test Input:**
- [ ] Enter IP: `192.168.1.100`
- [ ] Enter Port: `5555`
- [ ] Leave IP empty, click Next → should show error
- [ ] Enter IP, click Next → should advance

**Help Text:**
- [ ] Verify instructions mention "Developer Options"
- [ ] Verify instructions mention "Wireless debugging"
- [ ] Blue info box with phone icon visible

#### Test USB Form
**Steps:**
1. Click Back to return to Step 1
2. Select USB
3. Click Next
4. Verify shows:
   - "USB Connection" title
   - Info about USB debugging requirement
   - Gray box with "No additional configuration needed"
   - No input fields required

**Navigation:**
- [ ] Click Next → advances to Step 3

#### Test Pairing Form
**Steps:**
1. Click Back to Step 1
2. Select Pairing
3. Click Next
4. Verify fields shown:
   - Device IP Address
   - Pairing Port (default 37205)
   - Connection Port (default 5555)
   - Pairing Code (6-digit)
   - Detailed instructions panel

**Test Input:**
- [ ] Enter IP: `192.168.1.100`
- [ ] Keep default pairing port: `37205`
- [ ] Keep default connection port: `5555`
- [ ] Enter code: `123456`
- [ ] Leave code empty, click Next → should show error
- [ ] Fill all fields, click Next → advances

**Instructions Panel:**
- [ ] Shows "On your device:" header with phone icon
- [ ] Lists 4 steps for pairing setup
- [ ] Blue/gray background for visibility

#### Test Custom Form
Same as Wi-Fi test (IP + Port fields)

### 4. Step 3: Save Device

**Toggles:**
1. Verify "Save device for quick access" toggle
   - Default: ON
   - Description visible
2. Toggle OFF
   - Verify Device Name field disappears
   - Verify Favorite toggle disappears
3. Toggle back ON
   - Fields reappear

**Device Name:**
- [ ] Leave empty → defaults to `IP:port`
- [ ] Enter "My Test Device"
- [ ] Verify placeholder shows IP:port hint

**Favorite Toggle:**
- [ ] Default: OFF
- [ ] Toggle ON
- [ ] Verify star icon changes from outline to filled
- [ ] Verify star turns amber/gold

**Ready Panel:**
- [ ] Green-ish container visible
- [ ] Checkmark icon shown
- [ ] Text says "Ready to connect!"

### 5. Connection Flow

#### Test Wi-Fi Connection
**Setup:**
- Step 1: Select Wi-Fi
- Step 2: Enter IP `192.168.1.100`, Port `5555`
- Step 3: Toggle save ON, name "Test WiFi", favorite ON

**Connect:**
1. Click "Connect" button
2. Verify:
   - Button shows loading spinner
   - Text changes to "Connecting..."
   - Button disabled during connection
3. Wait for connection attempt
4. Check SnackBar:
   - Green background if success: "Connected successfully"
   - Red background if failed: "Connection failed"
5. If connection succeeds:
   - Dialog closes
   - Return to dashboard
   - Navigate to "Saved" tab
   - Find "Test WiFi" device
   - Verify star icon present (favorite)
   - Verify address shows `192.168.1.100:5555`

#### Test USB Connection
**Setup:**
- Step 1: Select USB
- Step 2: Click Next (no input needed)
- Step 3: Save ON, name "Test USB"

**Connect:**
1. Click "Connect"
2. Verify USB connection attempted
3. Check SnackBar for result
4. If saved, find in Saved tab

#### Test Pairing Connection
**Setup:**
- Step 1: Select Pairing
- Step 2: Enter all fields
- Step 3: Configure save options

**Connect:**
1. Click "Connect"
2. Should show: "Pairing not yet fully implemented"
3. Dialog remains open (can try again or close)

### 6. Save Device Verification

**If Save Toggle was ON:**
1. Close/complete wizard
2. Navigate to "Saved" tab in dashboard
3. Locate your device card
4. Verify:
   - [ ] Device name matches what you entered
   - [ ] Address shows correct IP:port
   - [ ] Star icon if marked as favorite
   - [ ] Card has all expected elements

**If Save Toggle was OFF:**
1. Close/complete wizard
2. Check Saved tab
3. Verify device NOT in list (connection attempted but not saved)

### 7. Error Handling

**Empty Required Fields:**
- [ ] Step 2: Leave IP empty, click Next → error message at bottom
- [ ] Step 2: Leave pairing code empty → error message
- [ ] Error has red/error color scheme
- [ ] Error icon visible

**Invalid Input:**
- [ ] Enter invalid IP format → connection fails
- [ ] Enter invalid port → connection fails
- [ ] Check SnackBar shows error details

**Network Errors:**
- [ ] Enter unreachable IP → connection timeout
- [ ] Verify error message clear
- [ ] Verify can retry

### 8. Navigation Flow

**Back Button:**
- [ ] Step 2: Click Back → returns to Step 1
- [ ] Step 3: Click Back → returns to Step 2
- [ ] Step 1: Back button not shown

**Close Button:**
- [ ] Click X in top right → dialog closes immediately
- [ ] No device saved
- [ ] Returns to dashboard

**Step Indicators:**
- [ ] Active step highlighted
- [ ] Completed steps show checkmark
- [ ] Future steps show number

### 9. Visual Design

**Dialog:**
- [ ] Max width 600px on desktop
- [ ] Max height 700px
- [ ] Scrollable if content overflows
- [ ] Proper padding (24px)

**Connection Type Cards:**
- [ ] 4 cards in wrapped row
- [ ] ~140px width each
- [ ] Icon + title + description
- [ ] Hover effect on desktop
- [ ] Selected state clearly visible

**Form Fields:**
- [ ] Material outlined style
- [ ] Prefix icons (e.g., devices, ethernet)
- [ ] Labels above fields
- [ ] Hints in lighter text
- [ ] Error state (red border) if validation fails

**Buttons:**
- [ ] "Back" - text button, left aligned
- [ ] "Next" - filled button, right aligned
- [ ] "Connect" - filled button with icon
- [ ] Proper spacing between buttons

**Colors:**
- [ ] Matches app theme
- [ ] Primary color for selected/active elements
- [ ] Error color for validation messages
- [ ] Surface colors for cards/containers

### 10. Responsiveness

**Desktop (1920x1080):**
- [ ] Dialog centered
- [ ] All content visible
- [ ] No scrolling needed for standard wizard

**Tablet (768px):**
- [ ] Dialog still centered
- [ ] Cards may wrap to 2x2 grid
- [ ] Touch targets adequate

**Mobile (360px):**
- [ ] Dialog fills most of screen
- [ ] Cards stack vertically
- [ ] All controls reachable
- [ ] Keyboard doesn't overlap fields

## Device Status Monitor Testing

The device status monitor service is created but not yet fully visible in the UI. To test at code level:

### Unit Test Approach

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:your_app/services/device_status_monitor.dart';
import 'package:your_app/models/saved_adb_device.dart';
import 'package:your_app/adb_client.dart';

void main() {
  test('Monitor checks device status', () async {
    final monitor = DeviceStatusMonitor();
    final device = SavedADBDevice(
      name: 'Test Device',
      host: '192.168.1.100',
      port: 5555,
      connectionType: ADBConnectionType.wifi,
    );
    
    final result = await monitor.checkNow(device);
    
    expect(result.deviceId, '192.168.1.100:5555');
    expect(result.isOnline, isA<bool>());
    expect(result.timestamp, isNotNull);
    
    monitor.dispose();
  });
}
```

### Manual Integration Test

1. Add to dashboard state:
   ```dart
   late final DeviceStatusMonitor _statusMonitor;
   
   @override
   void initState() {
     super.initState();
     _statusMonitor = DeviceStatusMonitor();
   }
   
   @override
   void dispose() {
     _statusMonitor.dispose();
     super.dispose();
   }
   ```

2. Start monitoring:
   ```dart
   for (final device in widget.savedDevices) {
     _statusMonitor.startMonitoring(device);
   }
   ```

3. Listen to updates:
   ```dart
   _statusMonitor.statusUpdates.listen((result) {
     print('Device ${result.deviceId}: ${result.statusText}');
   });
   ```

4. Check logs for status updates every 30 seconds

## Known Limitations

1. **Pairing Not Implemented**
   - Selecting pairing shows "not yet fully implemented" message
   - Can still test wizard flow, just can't complete pairing

2. **Status Monitor Not Visible**
   - Service works but not integrated into card UI
   - No latency badges shown yet
   - No status color indicators yet

3. **USB Device Names**
   - USB devices may show generic names
   - Depends on device info from USB bridge

## Success Criteria

Phase 3 is successful if:
- [x] Wizard opens from dashboard
- [x] All 3 steps navigate correctly
- [x] Connection type selection works
- [x] Forms show correct fields per type
- [x] Input validation prevents invalid submissions
- [x] Connection attempts work for Wi-Fi/USB
- [x] Devices save correctly when toggle ON
- [x] Devices not saved when toggle OFF
- [x] Favorites marked correctly
- [x] Dialog closes properly
- [x] No crashes or errors
- [ ] Status monitor service functional (code complete, UI pending)

## Comparison: Before vs After

### Before Phase 3
```
┌──────────────────────────────────┐
│ Add Device                    ×  │
├──────────────────────────────────┤
│ Connection Type: [Dropdown]      │
│ Host: [_______________]          │
│ Port: [_______________]          │
│ Pairing Port: [_______]          │
│ Pairing Code: [_______]          │
│                                  │
│ [Connect] [Save] [Close]         │
└──────────────────────────────────┘
```
All fields visible at once, confusing which to use.

### After Phase 3
```
Step 1: Choose Connection Type
┌──────────────────────────────────┐
│ ┌────┐ ┌────┐ ┌────┐ ┌────┐     │
│ │WiFi│ │USB │ │Pair│ │Cust│     │
│ └────┘ └────┘ └────┘ └────┘     │
│                     [Next] →     │
└──────────────────────────────────┘

Step 2: Enter Details (conditional)
┌──────────────────────────────────┐
│ Device IP: [192.168.1.100]       │
│ Port: [5555]                     │
│                                  │
│ ℹ️ Setup Instructions            │
│ ← [Back]           [Next] →      │
└──────────────────────────────────┘

Step 3: Save Options
┌──────────────────────────────────┐
│ ☑ Save device                    │
│ Name: [My Device]                │
│ ☐ Mark as favorite               │
│                                  │
│ ← [Back]        [Connect] →      │
└──────────────────────────────────┘
```
Clear progression, focused inputs, guidance included.

## Tips for Best Experience

1. **Test with Real Device:** Have an Android device with wireless debugging enabled for realistic testing

2. **Check Network:** Ensure test device and computer on same network for Wi-Fi connections

3. **Enable USB Debugging:** For USB tests, enable debugging and authorize computer

4. **Watch Logs:** Keep terminal visible to see connection attempt logs

5. **Test All Paths:** Try completing wizard AND canceling at each step

6. **Verify Persistence:** Close app and reopen to verify saved devices persist

## What to Look For

### Good Signs ✅
- Wizard opens smoothly
- Step transitions are smooth
- Forms validate correctly
- Connection attempts provide feedback
- Devices save and persist
- UI matches Material 3 design
- No console errors

### Red Flags ❌
- Wizard doesn't open
- Steps skip or go backward unexpectedly
- Validation allows invalid data
- Connection hangs forever
- Devices don't appear in Saved tab
- Crashes or exceptions
- UI elements overlap or misalign

## Feedback Prompts

After testing, please provide feedback on:

1. **Wizard UX:**
   - Is the flow intuitive?
   - Are instructions clear?
   - Any confusing steps?

2. **Visual Design:**
   - Does it look professional?
   - Colors appropriate?
   - Spacing good?

3. **Connection Success:**
   - Did connections work?
   - Were errors helpful?
   - Any timeouts?

4. **Save Functionality:**
   - Devices saved correctly?
   - Favorites working?
   - Labels/names correct?

5. **Missing Features:**
   - What would make it better?
   - Any frustrations?
   - Desired improvements?

## Next Steps

After testing Phase 3:

1. **Report Issues:** Note any bugs, crashes, or unexpected behavior

2. **Request Enhancements:** Suggest improvements to wizard flow

3. **Phase 4 Discussion:** Discuss integrating status monitor into card UI

4. **Pairing Implementation:** Decide if pairing functionality is needed

5. **Additional Features:** Consider QR scanning, device discovery, etc.

---

**Ready to Test!** Open the app, navigate to ADB Manager > Dashboard > New Connection, and start testing the wizard. Good luck! 🚀
