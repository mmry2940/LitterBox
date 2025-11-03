# Raspberry Pi Connect - Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            FLUTTER APP (ANDROID)                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────┐    │
│  │                     RpiConnectScreen Widget                         │    │
│  ├────────────────────────────────────────────────────────────────────┤    │
│  │                                                                      │    │
│  │  [Connection Controls]                                              │    │
│  │  ┌──────────────────────────────────────────────────────────┐      │    │
│  │  │ Signaling Server: ws://raspberrypi.local:8080          │      │    │
│  │  │ Device ID: my-raspberry-pi                              │      │    │
│  │  │ [Connect Button]                                         │      │    │
│  │  └──────────────────────────────────────────────────────────┘      │    │
│  │                                                                      │    │
│  │  [Status Bar]                                                       │    │
│  │  ● Connected | Live                                                 │    │
│  │                                                                      │    │
│  │  [Video Display]                                                    │    │
│  │  ┌──────────────────────────────────────────────────────────┐      │    │
│  │  │                                                           │      │    │
│  │  │         RTCVideoView (Remote Desktop)                    │      │    │
│  │  │                                                           │      │    │
│  │  │                                                           │      │    │
│  │  └──────────────────────────────────────────────────────────┘      │    │
│  │                                                                      │    │
│  │  [Control Buttons]                                                  │    │
│  │  [Fullscreen] [Screenshot] [Disconnect]                            │    │
│  │                                                                      │    │
│  └────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────┐    │
│  │                    WebRTC Components                                │    │
│  ├────────────────────────────────────────────────────────────────────┤    │
│  │                                                                      │    │
│  │  RTCPeerConnection                                                  │    │
│  │  ├── ICE Candidates (STUN/TURN)                                    │    │
│  │  ├── SDP Offer/Answer                                              │    │
│  │  └── DTLS/SRTP Encryption                                          │    │
│  │                                                                      │    │
│  │  RTCVideoRenderer                                                   │    │
│  │  └── Displays incoming video stream                                │    │
│  │                                                                      │    │
│  │  WebRTCSignalingService                                             │    │
│  │  └── WebSocket connection to signaling server                      │    │
│  │                                                                      │    │
│  └────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
└─────────────────────────────────┬────────────────────────────────────────────┘
                                  │
                                  │ WebSocket (Signaling)
                                  │ ws://server:8080
                                  │
┌─────────────────────────────────▼────────────────────────────────────────────┐
│                          SIGNALING SERVER (Node.js)                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  signaling-server.js                                                         │
│  ┌────────────────────────────────────────────────────────────────────┐    │
│  │                                                                      │    │
│  │  Client Management                                                  │    │
│  │  ├── Connected Clients Map                                          │    │
│  │  ├── Role Tracking (Broadcaster/Viewer)                             │    │
│  │  └── Device Registry                                                │    │
│  │                                                                      │    │
│  │  Message Router                                                     │    │
│  │  ├── Forward SDP Offers/Answers                                     │    │
│  │  ├── Exchange ICE Candidates                                        │    │
│  │  └── Device Discovery                                               │    │
│  │                                                                      │    │
│  │  WebSocket Server (port 8080)                                       │    │
│  │  └── Maintains persistent connections                               │    │
│  │                                                                      │    │
│  └────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
└─────────────────────────────────┬────────────────────────────────────────────┘
                                  │
                                  │ WebSocket (Signaling)
                                  │
┌─────────────────────────────────▼────────────────────────────────────────────┐
│                          RASPBERRY PI (Broadcaster)                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────┐    │
│  │                    WebRTC Server (Node.js)                          │    │
│  ├────────────────────────────────────────────────────────────────────┤    │
│  │                                                                      │    │
│  │  RTCPeerConnection                                                  │    │
│  │  ├── Receives Offer from Viewer                                     │    │
│  │  ├── Generates Answer                                               │    │
│  │  ├── Exchanges ICE Candidates                                       │    │
│  │  └── Establishes P2P Connection                                     │    │
│  │                                                                      │    │
│  │  Screen Capture                                                     │    │
│  │  ├── WayVNC (Wayland)                                               │    │
│  │  └── OR FFmpeg (X11grab)                                            │    │
│  │                                                                      │    │
│  │  Video Encoding                                                     │    │
│  │  ├── H.264 Codec                                                    │    │
│  │  ├── Hardware Acceleration (if available)                           │    │
│  │  └── Adjustable Quality/Framerate                                   │    │
│  │                                                                      │    │
│  └────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────┐    │
│  │                         Desktop Environment                          │    │
│  ├────────────────────────────────────────────────────────────────────┤    │
│  │                                                                      │    │
│  │  Wayland Compositor (or X11)                                        │    │
│  │  └── Running Desktop Session                                        │    │
│  │                                                                      │    │
│  └────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘


═══════════════════════════════════════════════════════════════════════════════
                              CONNECTION FLOW
═══════════════════════════════════════════════════════════════════════════════

Phase 1: SIGNALING (via WebSocket)
───────────────────────────────────────────────────────────────────────────────

  Flutter App                Signaling Server           Raspberry Pi
      │                             │                         │
      │ ──── Connect WS ─────────> │                         │
      │ <─── ID: client_123 ─────  │                         │
      │                             │ <──── Register ────────│
      │                             │       (deviceId: rpi1)  │
      │                             │                         │
      │ ──── Create Offer ───────> │                         │
      │      (SDP)                  │                         │
      │                             │ ───── Forward ──────>  │
      │                             │       Offer (SDP)       │
      │                             │                         │
      │                             │ <───── Answer ─────────│
      │ <──── Forward ────────────  │        (SDP)           │
      │       Answer (SDP)          │                         │
      │                             │                         │
      │ ──── ICE Candidate ──────> │                         │
      │                             │ ───── Forward ──────>  │
      │                             │                         │
      │                             │ <───── ICE ────────────│
      │ <──── Forward ────────────  │       Candidate         │
      │       ICE Candidate         │                         │
      │                             │                         │


Phase 2: PEER-TO-PEER CONNECTION (WebRTC Direct)
───────────────────────────────────────────────────────────────────────────────

  Flutter App                                           Raspberry Pi
      │                                                       │
      │ <═══════════════════════════════════════════════════>│
      │           Direct P2P Connection Established          │
      │              (DTLS/SRTP Encrypted)                   │
      │                                                       │
      │ <─────────────── Video Stream ───────────────────────│
      │         (H.264, encrypted, real-time)                │
      │                                                       │
      │ ─────────────── Input Events ───────────────────────>│
      │          (Mouse/Keyboard - future)                   │
      │                                                       │


═══════════════════════════════════════════════════════════════════════════════
                            NETWORK TOPOLOGY
═══════════════════════════════════════════════════════════════════════════════

Local Network (Direct P2P):
┌─────────────┐                                    ┌──────────────┐
│             │◄──────── Direct WebRTC ──────────► │              │
│ Flutter App │          (Low Latency)             │ Raspberry Pi │
│             │◄──────── < 50ms delay ────────────►│              │
└─────────────┘                                    └──────────────┘


Internet Connection (via TURN):
┌─────────────┐         ┌────────────┐         ┌──────────────┐
│             │◄───────►│            │◄───────►│              │
│ Flutter App │  WebRTC │ TURN Server│  WebRTC │ Raspberry Pi │
│             │◄───────►│  (Relay)   │◄───────►│              │
└─────────────┘         └────────────┘         └──────────────┘
                       (Higher Latency)


═══════════════════════════════════════════════════════════════════════════════
                              DATA FLOW
═══════════════════════════════════════════════════════════════════════════════

Raspberry Pi Side:
┌──────────────┐    ┌──────────┐    ┌─────────┐    ┌─────────┐
│   Desktop    │───►│  Screen  │───►│ Encode  │───►│ Encrypt │
│   (Wayland)  │    │ Capture  │    │ (H.264) │    │ (DTLS)  │
└──────────────┘    └──────────┘    └─────────┘    └────┬────┘
                                                         │
                                                         ▼
                                                 ┌───────────────┐
                                                 │ WebRTC Send   │
                                                 │ (UDP Packets) │
                                                 └───────┬───────┘
                                                         │
                             Internet / Local Network ───┤
                                                         │
Flutter App Side:                                       ▼
                                                 ┌───────────────┐
                                                 │ WebRTC Receive│
                                                 └───────┬───────┘
                                                         │
┌──────────────┐    ┌──────────┐    ┌─────────┐    ┌───▼─────┐
│   Display    │◄───│  Render  │◄───│ Decode  │◄───│ Decrypt │
│ (RTCVideo    │    │ (Flutter)│    │ (H.264) │    │ (DTLS)  │
│  View)       │    │          │    │         │    │         │
└──────────────┘    └──────────┘    └─────────┘    └─────────┘


═══════════════════════════════════════════════════════════════════════════════
                            SECURITY LAYERS
═══════════════════════════════════════════════════════════════════════════════

┌─────────────────────────────────────────────────────────────────────────────┐
│                             Application Layer                                │
│                        (LitterBox Flutter App)                               │
└────────────────────────────────┬────────────────────────────────────────────┘
                                 │
┌────────────────────────────────▼────────────────────────────────────────────┐
│                         WebRTC Layer (DTLS/SRTP)                             │
│                      ◄ End-to-End Encryption ►                               │
└────────────────────────────────┬────────────────────────────────────────────┘
                                 │
┌────────────────────────────────▼────────────────────────────────────────────┐
│                        Transport Layer (UDP/TCP)                             │
│                           ICE/STUN/TURN                                      │
└────────────────────────────────┬────────────────────────────────────────────┘
                                 │
┌────────────────────────────────▼────────────────────────────────────────────┐
│                         Network Layer (IP)                                   │
│                    WiFi / Ethernet / Mobile                                  │
└─────────────────────────────────────────────────────────────────────────────┘


═══════════════════════════════════════════════════════════════════════════════
                          FILE STRUCTURE
═══════════════════════════════════════════════════════════════════════════════

LitterBox/
├── lib/
│   ├── screens/
│   │   └── rpi_connect_screen.dart          ← Main WebRTC screen
│   └── services/
│       └── webrtc_signaling_service.dart    ← WebSocket signaling
│
├── signaling-server.js                      ← Node.js signaling server
│
├── RPI_CONNECT_SETUP.md                     ← Raspberry Pi setup guide
├── RPI_CONNECT_IMPLEMENTATION.md            ← Technical details
├── RPI_CONNECT_SUMMARY.md                   ← Complete summary
└── ARCHITECTURE.md                          ← This file


═══════════════════════════════════════════════════════════════════════════════
                            KEY CONCEPTS
═══════════════════════════════════════════════════════════════════════════════

WebRTC Signaling:
  • NOT part of WebRTC standard
  • Used to exchange connection info (SDP, ICE)
  • Can use any protocol (WebSocket, HTTP, etc.)
  • Our implementation uses WebSocket

SDP (Session Description Protocol):
  • Describes media capabilities
  • Offer: "This is what I can send/receive"
  • Answer: "This is what I'll send/receive"

ICE (Interactive Connectivity Establishment):
  • Finds best network path
  • Tests multiple candidates (local, STUN, TURN)
  • Automatically handles NAT traversal

STUN (Session Traversal Utilities for NAT):
  • Discovers public IP address
  • Free public servers available
  • Used for direct P2P connections

TURN (Traversal Using Relays around NAT):
  • Relays traffic when direct connection fails
  • Requires dedicated server
  • Higher latency but guaranteed connectivity

DTLS (Datagram Transport Layer Security):
  • TLS for UDP
  • Encrypts all WebRTC media
  • Mandatory in WebRTC

SRTP (Secure Real-time Transport Protocol):
  • Encrypts audio/video streams
  • Works with DTLS for key exchange
  • Prevents eavesdropping


═══════════════════════════════════════════════════════════════════════════════
```
