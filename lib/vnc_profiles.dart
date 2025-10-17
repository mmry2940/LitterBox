import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// VNC connection profile for common server configurations
class VNCProfile {
  final String name;
  final String description;
  final String host;
  final int port;
  final String? password;
  final int securityType; // 1=None, 2=VNC, 5=RA2, etc.
  final bool shareDesktop;
  final List<int> preferredEncodings;
  final VNCDisplaySettings displaySettings;
  final VNCInputSettings inputSettings;

  const VNCProfile({
    required this.name,
    required this.description,
    required this.host,
    this.port = 5900,
    this.password,
    this.securityType = 2, // VNC authentication by default
    this.shareDesktop = true,
    this.preferredEncodings = const [
      16,
      15,
      5,
      2,
      1,
      0
    ], // ZRLE, TRLE, Hextile, RRE, CopyRect, Raw
    required this.displaySettings,
    required this.inputSettings,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'host': host,
      'port': port,
      'password': password,
      'securityType': securityType,
      'shareDesktop': shareDesktop,
      'preferredEncodings': preferredEncodings,
      'displaySettings': displaySettings.toJson(),
      'inputSettings': inputSettings.toJson(),
    };
  }

  factory VNCProfile.fromJson(Map<String, dynamic> json) {
    return VNCProfile(
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      host: json['host'] ?? '',
      port: json['port'] ?? 5900,
      password: json['password'],
      securityType: json['securityType'] ?? 2,
      shareDesktop: json['shareDesktop'] ?? true,
      preferredEncodings:
          List<int>.from(json['preferredEncodings'] ?? [16, 15, 5, 2, 1, 0]),
      displaySettings:
          VNCDisplaySettings.fromJson(json['displaySettings'] ?? {}),
      inputSettings: VNCInputSettings.fromJson(json['inputSettings'] ?? {}),
    );
  }
}

/// Display settings for VNC connections
class VNCDisplaySettings {
  final String scalingMode; // 'fitToScreen', 'actualSize', 'autoFitWidth', etc.
  final bool fullscreen;
  final int colorDepth; // 8, 16, 24, 32
  final bool showCursor;
  final bool viewOnly;

  const VNCDisplaySettings({
    this.scalingMode = 'autoFitWidth',
    this.fullscreen = false,
    this.colorDepth = 32,
    this.showCursor = true,
    this.viewOnly = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'scalingMode': scalingMode,
      'fullscreen': fullscreen,
      'colorDepth': colorDepth,
      'showCursor': showCursor,
      'viewOnly': viewOnly,
    };
  }

  factory VNCDisplaySettings.fromJson(Map<String, dynamic> json) {
    return VNCDisplaySettings(
      scalingMode: json['scalingMode'] ?? 'autoFitWidth',
      fullscreen: json['fullscreen'] ?? false,
      colorDepth: json['colorDepth'] ?? 32,
      showCursor: json['showCursor'] ?? true,
      viewOnly: json['viewOnly'] ?? false,
    );
  }
}

/// Input settings for VNC connections
class VNCInputSettings {
  final String
      inputMode; // 'directTouch', 'trackpadMode', 'directTouchWithZoom'
  final bool enableKeyboard;
  final bool enableClipboard;
  final double touchSensitivity;
  final bool enableGestures;

  const VNCInputSettings({
    this.inputMode = 'directTouch',
    this.enableKeyboard = true,
    this.enableClipboard = true,
    this.touchSensitivity = 1.0,
    this.enableGestures = true,
  });

  Map<String, dynamic> toJson() {
    return {
      'inputMode': inputMode,
      'enableKeyboard': enableKeyboard,
      'enableClipboard': enableClipboard,
      'touchSensitivity': touchSensitivity,
      'enableGestures': enableGestures,
    };
  }

  factory VNCInputSettings.fromJson(Map<String, dynamic> json) {
    return VNCInputSettings(
      inputMode: json['inputMode'] ?? 'directTouch',
      enableKeyboard: json['enableKeyboard'] ?? true,
      enableClipboard: json['enableClipboard'] ?? true,
      touchSensitivity: json['touchSensitivity']?.toDouble() ?? 1.0,
      enableGestures: json['enableGestures'] ?? true,
    );
  }
}

/// Profile manager for VNC connections
class VNCProfileManager {
  static const String _profilesKey = 'vnc_profiles';
  static const String _lastUsedProfileKey = 'vnc_last_used_profile';

  /// Get predefined common profiles
  static List<VNCProfile> getCommonProfiles() {
    return [
      // Windows Remote Desktop (RealVNC)
      VNCProfile(
        name: 'Windows Desktop',
        description: 'Standard Windows VNC server (RealVNC)',
        host: '',
        port: 5900,
        securityType: 2, // VNC authentication
        preferredEncodings: [16, 15, 5, 2, 1, 0], // Optimized for Windows
        displaySettings: const VNCDisplaySettings(
          scalingMode: 'autoFitWidth',
          colorDepth: 32,
          showCursor: true,
        ),
        inputSettings: const VNCInputSettings(
          inputMode: 'directTouch',
          enableKeyboard: true,
          enableClipboard: true,
        ),
      ),

      // Linux Desktop
      VNCProfile(
        name: 'Linux Desktop',
        description: 'Standard Linux VNC server (TigerVNC)',
        host: '',
        port: 5901,
        securityType: 2,
        preferredEncodings: [15, 5, 2, 1, 0], // TRLE works well on Linux
        displaySettings: const VNCDisplaySettings(
          scalingMode: 'autoFitWidth',
          colorDepth: 24, // Often better on Linux
          showCursor: true,
        ),
        inputSettings: const VNCInputSettings(
          inputMode: 'directTouch',
          enableKeyboard: true,
          enableClipboard: true,
        ),
      ),

      // macOS Screen Sharing
      VNCProfile(
        name: 'macOS Screen Sharing',
        description: 'macOS built-in screen sharing',
        host: '',
        port: 5900,
        securityType: 2,
        preferredEncodings: [5, 2, 1, 0], // Hextile works well on macOS
        displaySettings: const VNCDisplaySettings(
          scalingMode: 'autoFitWidth',
          colorDepth: 32,
          showCursor: true,
        ),
        inputSettings: const VNCInputSettings(
          inputMode: 'trackpadMode', // Better for macOS
          enableKeyboard: true,
          enableClipboard: true,
        ),
      ),

      // Headless Server
      VNCProfile(
        name: 'Headless Server',
        description: 'Headless server or Raspberry Pi',
        host: '',
        port: 5900,
        securityType: 2,
        preferredEncodings: [2, 1, 0], // Minimal encodings for low bandwidth
        displaySettings: const VNCDisplaySettings(
          scalingMode: 'fitToScreen',
          colorDepth: 16, // Lower color depth for performance
          showCursor: false,
        ),
        inputSettings: const VNCInputSettings(
          inputMode: 'directTouch',
          enableKeyboard: true,
          enableClipboard: false, // Often not needed
          touchSensitivity: 0.8,
        ),
      ),

      // High-Performance Workstation
      VNCProfile(
        name: 'High-Performance',
        description: 'High-performance workstation with fast network',
        host: '',
        port: 5900,
        securityType: 2,
        preferredEncodings: [0, 1], // Raw and CopyRect for best quality
        displaySettings: const VNCDisplaySettings(
          scalingMode: 'actualSize',
          colorDepth: 32,
          showCursor: true,
        ),
        inputSettings: const VNCInputSettings(
          inputMode: 'directTouchWithZoom',
          enableKeyboard: true,
          enableClipboard: true,
          touchSensitivity: 1.0,
          enableGestures: true,
        ),
      ),

      // Low Bandwidth
      VNCProfile(
        name: 'Low Bandwidth',
        description: 'Optimized for slow connections',
        host: '',
        port: 5900,
        securityType: 2,
        preferredEncodings: [16, 15, 2], // Compressed encodings only
        displaySettings: const VNCDisplaySettings(
          scalingMode: 'fitToScreen',
          colorDepth: 8, // Minimal color depth
          showCursor: false,
        ),
        inputSettings: const VNCInputSettings(
          inputMode: 'trackpadMode',
          enableKeyboard: true,
          enableClipboard: false,
          touchSensitivity: 0.5,
          enableGestures: false,
        ),
      ),
    ];
  }

  /// Save a custom profile
  static Future<void> saveProfile(VNCProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    final profiles = await getCustomProfiles();

    // Remove existing profile with same name
    profiles.removeWhere((p) => p.name == profile.name);
    profiles.add(profile);

    final profilesJson = profiles.map((p) => p.toJson()).toList();
    await prefs.setString(_profilesKey, jsonEncode(profilesJson));
  }

  /// Get saved custom profiles
  static Future<List<VNCProfile>> getCustomProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final profilesString = prefs.getString(_profilesKey);

    if (profilesString == null) return [];

    try {
      final profilesJson = jsonDecode(profilesString) as List;
      return profilesJson.map((json) => VNCProfile.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Get all profiles (common + custom)
  static Future<List<VNCProfile>> getAllProfiles() async {
    final customProfiles = await getCustomProfiles();
    final commonProfiles = getCommonProfiles();

    return [...commonProfiles, ...customProfiles];
  }

  /// Delete a custom profile
  static Future<void> deleteProfile(String profileName) async {
    final prefs = await SharedPreferences.getInstance();
    final profiles = await getCustomProfiles();

    profiles.removeWhere((p) => p.name == profileName);

    final profilesJson = profiles.map((p) => p.toJson()).toList();
    await prefs.setString(_profilesKey, jsonEncode(profilesJson));
  }

  /// Save last used profile name
  static Future<void> saveLastUsedProfile(String profileName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastUsedProfileKey, profileName);
  }

  /// Get last used profile name
  static Future<String?> getLastUsedProfileName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastUsedProfileKey);
  }

  /// Create a profile from current connection settings
  static VNCProfile createProfileFromSettings({
    required String name,
    required String description,
    required String host,
    required int port,
    String? password,
    required String scalingMode,
    required String inputMode,
  }) {
    return VNCProfile(
      name: name,
      description: description,
      host: host,
      port: port,
      password: password,
      displaySettings: VNCDisplaySettings(
        scalingMode: scalingMode,
      ),
      inputSettings: VNCInputSettings(
        inputMode: inputMode,
      ),
    );
  }
}
