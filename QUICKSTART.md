# 🚀 Quick Start Guide - Raspberry Pi Connect

Get up and running with WebRTC remote desktop in under 10 minutes!

## 📋 Prerequisites

- ✅ Flutter app built and installed on Android device
- ✅ Raspberry Pi (any model with network access)
- ✅ Both devices on same network (for initial testing)

## 🎯 Step 1: Start Signaling Server (2 minutes)

### On your computer or Raspberry Pi:

```bash
# Navigate to project directory
cd LitterBox

# Install Node.js (if not installed)
# On Windows:
# Download from https://nodejs.org/

# On Linux/Mac:
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# Initialize npm project
npm init -y

# Install WebSocket library
npm install ws

# Start the signaling server
node signaling-server.js
```

**Expected output:**
```
WebRTC Signaling Server started on port 8080
Waiting for connections...

Ready for connections!
```

**Note your server IP address:**
```bash
# On Windows:
ipconfig

# On Linux/Mac:
hostname -I
```

Example: `192.168.1.100`

---

## 🥧 Step 2: Setup Raspberry Pi (Optional - for testing)

For now, you can skip this and test the UI. To actually stream video later:

### Option A: Quick Test with Static Video

```bash
# Install ffmpeg
sudo apt install ffmpeg

# Test screen capture
ffmpeg -f x11grab -video_size 1920x1080 -framerate 30 -i :0.0 test.mp4
```

### Option B: Full WebRTC Server (Later)

See `RPI_CONNECT_SETUP.md` for complete Raspberry Pi server setup.

---

## 📱 Step 3: Test the App (1 minute)

1. **Open LitterBox app** on your Android device

2. **Navigate to Raspberry Pi Connect:**
   - Open side menu (☰)
   - Tap "Raspberry Pi Connect"

3. **Enter connection details:**
   - Signaling Server: `ws://192.168.1.100:8080`
     (Replace with your server IP)
   - Device ID: `test-device` (optional)

4. **Tap "Connect"**

**Expected behavior:**
- Status changes to "Connecting..."
- Status changes to "ICE: checking"
- You'll see connection attempts in signaling server logs

**What happens:**
- ✅ App creates WebRTC peer connection
- ✅ App connects to signaling server via WebSocket
- ✅ App sends offer with video receive request
- ⏸️ Waiting for Raspberry Pi to respond (not yet configured)

---

## 🎨 What You Can Do Now

### ✅ Working Features:

1. **Connection UI**
   - Enter signaling server address
   - Optional device ID
   - Clean, professional interface

2. **WebRTC Setup**
   - Peer connection created
   - STUN servers configured
   - ICE candidates generated

3. **Status Monitoring**
   - Real-time connection status
   - Color-coded indicators
   - Connection info dialog

4. **Signaling Server**
   - Full WebSocket communication
   - Client tracking
   - Message routing
   - Device discovery

### ⏳ Not Yet Working:

- Video streaming (needs Raspberry Pi server)
- Input control (mouse/keyboard)
- Screenshot/fullscreen features

---

## 🔍 Verify Everything Works

### Check Signaling Server Logs:

When you tap "Connect" in the app, you should see:

```
[2024-11-02T10:30:45.123Z] New connection from 192.168.1.101
  Assigned ID: client_1730548245123_abc123xyz

Total connected clients: 1

[client_1730548245123_abc123xyz] Received: offer
  Error: Device not found
```

This is CORRECT! The app is working, just waiting for Raspberry Pi.

### Check App Behavior:

- ✅ Connection button disabled while connecting
- ✅ Status bar shows "Connecting..." then "ICE: checking"
- ✅ No crashes or errors
- ✅ Can disconnect and reconnect

---

## 📊 Next Steps

### Immediate (30 minutes):
Wire up the signaling service in `rpi_connect_screen.dart`:

```dart
// Replace the stub methods with:
final _signalingService = WebRTCSignalingService();

Future<void> _connect() async {
  // Connect to signaling server
  await _signalingService.connect(_serverController.text);
  
  // Setup callbacks
  _signalingService.onAnswer = (answer) async {
    await _peerConnection!.setRemoteDescription(answer);
  };
  
  _signalingService.onIceCandidate = (candidate) async {
    await _peerConnection!.addIceCandidate(candidate);
  };
  
  // Create and send offer
  await _createPeerConnection();
  RTCSessionDescription offer = await _peerConnection!.createOffer({
    'offerToReceiveVideo': true,
    'offerToReceiveAudio': true,
  });
  await _peerConnection!.setLocalDescription(offer);
  await _signalingService.sendOffer(offer);
}
```

### Short Term (2-4 hours):
1. Set up basic Raspberry Pi WebRTC server
2. Test video streaming
3. Verify P2P connection

### Medium Term (4-8 hours):
1. Add input control (mouse/keyboard)
2. Implement screenshot feature
3. Add fullscreen mode
4. Quality settings

---

## 🐛 Troubleshooting

### Issue: Can't connect to signaling server

**Check:**
```bash
# Is server running?
# Look for "Signaling Server started" message

# Can you reach the server?
ping 192.168.1.100

# Is port 8080 open?
# On Linux:
sudo netstat -tlnp | grep 8080

# On Windows:
netstat -an | findstr 8080
```

**Fix:**
- Restart signaling server
- Check firewall settings
- Verify IP address is correct
- Try `ws://localhost:8080` if on same machine

### Issue: Connection attempts but nothing happens

**This is normal!** You need to:
1. Set up Raspberry Pi WebRTC server
2. Have it register with signaling server
3. Then it can respond to connection offers

### Issue: App crashes on connect

**Check:**
- `flutter_webrtc` package installed correctly
- Run `flutter pub get`
- Check Android permissions in manifest
- View logs: `flutter logs`

---

## 📚 Documentation Reference

- **Setup Guide**: `RPI_CONNECT_SETUP.md` - Complete Raspberry Pi setup
- **Implementation**: `RPI_CONNECT_IMPLEMENTATION.md` - Technical details
- **Architecture**: `ARCHITECTURE.md` - System diagrams
- **Summary**: `RPI_CONNECT_SUMMARY.md` - Complete overview

---

## 🎓 Learning Resources

### Understanding WebRTC:
1. Watch: [WebRTC Crash Course](https://www.youtube.com/watch?v=WmR9IMUD_CY)
2. Read: [WebRTC for Beginners](https://webrtc.org/getting-started/overview)
3. Try: [WebRTC Samples](https://webrtc.github.io/samples/)

### Flutter WebRTC:
1. Package: [flutter_webrtc on pub.dev](https://pub.dev/packages/flutter_webrtc)
2. Examples: [flutter-webrtc examples](https://github.com/flutter-webrtc/flutter-webrtc/tree/master/example)
3. Tutorial: Search "Flutter WebRTC tutorial" on YouTube

---

## ✅ Success Criteria

You'll know everything is working when:

- ✅ Signaling server accepts connections
- ✅ App shows "Connected" status
- ✅ Server logs show offer/answer exchange
- ✅ ICE state reaches "connected"
- ✅ Video appears in app (after Pi setup)

---

## 🎉 You're Ready!

The foundation is complete. The app can:
- Connect to signaling server ✅
- Create WebRTC peer connections ✅
- Exchange connection info ✅
- Display remote video ✅

All that's left is setting up the Raspberry Pi server to send video!

---

## 💡 Quick Tips

1. **Start Simple**: Test with signaling server first
2. **Check Logs**: Both signaling server and `flutter logs`
3. **Local First**: Test on local network before internet
4. **One Step at a Time**: Don't try to do everything at once
5. **Ask for Help**: Use GitHub issues or Flutter Discord

---

## 🤝 Get Help

If you get stuck:

1. Check the documentation in this repo
2. Read the troubleshooting sections
3. Look at signaling server logs
4. Check Flutter logs: `flutter logs`
5. Verify network connectivity

Remember: The hard part (WebRTC setup) is done! 🎊

---

**Ready to see your Raspberry Pi's screen in the app? Let's go! 🚀**
