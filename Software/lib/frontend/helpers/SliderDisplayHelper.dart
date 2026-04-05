import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:mixlit/backend/application/audio/ApplicationManager.dart';
import 'package:mixlit/backend/application/audio/audio_service_client.dart';
import 'package:mixlit/backend/application/data/ConfigManager.dart';
import 'package:mixlit/frontend/components/ApplicationIcon.dart';
import 'package:mixlit/frontend/Theme.dart';

class SliderDisplayHelper {
  ApplicationManager applicationManager;
  List<AudioSessionInfo?> assignedApps;
  List<String> sliderTags;
  Map<String, Uint8List?> appIcons;
  Map<String, Uint8List?> cachedAppIcons;

  SliderDisplayHelper({
    required this.applicationManager,
    required this.assignedApps,
    required this.sliderTags,
    required this.appIcons,
    required this.cachedAppIcons,
  });

  void updateAssignedApps(List<AudioSessionInfo?> newApps) {
    assignedApps = newApps;
  }

  // ── Icons ──────────────────────────────────────────────────────────────────

  Widget buildSliderIcon(int index) =>
      _buildIcon(index, size: AppTheme.iconSizeLarge);

  Widget buildDialIcon(int index) =>
      _buildIcon(index, size: AppTheme.iconSizeMedium);

  Widget _buildIcon(int index, {required double size}) {
    final tag = sliderTags[index];
    final app = assignedApps[index];
    final hasMissing =
        applicationManager.missingApplications.containsKey(index);
    final hasGroup = applicationManager.assignedGroups.containsKey(index);
    final hasIntegration =
        applicationManager.assignedIntegrations.containsKey(index);

    if (tag == ConfigManager.TAG_INTEGRATION) {
      if (hasIntegration) {
        return _integrationIcon(
            applicationManager.assignedIntegrations[index]!, size);
      }
      return Icon(Icons.error_outline, color: Colors.orange, size: size);
    }

    switch (tag) {
      case ConfigManager.TAG_DEFAULT_DEVICE:
        return Icon(Icons.speaker, color: Colors.white, size: size);
      case ConfigManager.TAG_MASTER_VOLUME:
        return Icon(Icons.volume_up, color: Colors.white, size: size);
      case ConfigManager.TAG_ACTIVE_APP:
        return Icon(Icons.app_registration, color: Colors.white, size: size);
      case ConfigManager.TAG_GROUP:
        if (hasGroup) {
          final group = applicationManager.assignedGroups[index]!;
          return _groupIcon(group.color, size);
        }
        break;
      case ConfigManager.TAG_APP:
        return _appIcon(index, app, hasMissing, size);
    }

    return Icon(Icons.add_circle_outline, color: Colors.white, size: size);
  }

  Widget _integrationIcon(Map<String, dynamic> integration, double size) {
    final path = switch (integration['type']) {
      'spotify' => 'lib/frontend/assets/images/logo/integrations/Spotify.png',
      'sonos' => 'lib/frontend/assets/images/logo/integrations/Sonos.png',
      _ => null,
    };
    if (path == null) return Icon(Icons.power, color: Colors.white, size: size);
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(path, fit: BoxFit.contain),
    );
  }

  Widget _groupIcon(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.folder,
          color: Colors.white, size: size > 24 ? 24 : size * 0.75),
    );
  }

  Widget _appIcon(
      int index, AudioSessionInfo? app, bool hasMissing, double fallbackSize) {
    if (app != null) {
      final iconData = appIcons[app.processPath];
      if (iconData != null) return ApplicationIcon(iconData: iconData);
    } else if (hasMissing) {
      final missing = applicationManager.missingApplications[index]!;
      final cached = cachedAppIcons[missing.processName];
      if (cached != null) return ApplicationIcon(iconData: cached);
    }
    return Icon(Icons.apps, color: Colors.white, size: fallbackSize);
  }

  String buildSliderTitle(int index) => _title(index, multiline: true);
  String buildDialTitle(int index) => _title(index, multiline: false);

  String _title(int index, {required bool multiline}) {
    final tag = sliderTags[index];
    final app = assignedApps[index];
    final hasGroup = applicationManager.assignedGroups.containsKey(index);
    final hasIntegration =
        applicationManager.assignedIntegrations.containsKey(index);

    if (tag == ConfigManager.TAG_INTEGRATION && hasIntegration) {
      final data = applicationManager.assignedIntegrations[index];
      return data?['displayName'] ??
          data?['deviceName'] ??
          data?['type'] ??
          'Integration';
    }

    switch (tag) {
      case ConfigManager.TAG_DEFAULT_DEVICE:
        return 'Device';
      case ConfigManager.TAG_MASTER_VOLUME:
        return multiline ? 'Master\nVolume' : 'Master Volume';
      case ConfigManager.TAG_ACTIVE_APP:
        return multiline ? 'Active\nApp' : 'Active App';
      case ConfigManager.TAG_GROUP:
        if (hasGroup) return applicationManager.assignedGroups[index]!.name;
        break;
      case ConfigManager.TAG_APP:
        if (app != null) {
          final raw = app.processPath.split(r'\').last.replaceAll('.exe', '');
          return raw.isEmpty
              ? 'Unknown'
              : raw[0].toUpperCase() + raw.substring(1);
        }
        final missing = applicationManager.missingApplications[index];
        if (missing != null) return missing.displayName;
        break;
    }

    return 'N/A';
  }

  bool isSliderActive(int index) {
    final tag = sliderTags[index];
    if (tag == ConfigManager.TAG_UNASSIGNED) return false;
    if (tag == ConfigManager.TAG_INTEGRATION) {
      return applicationManager.assignedIntegrations.containsKey(index);
    }
    if (tag == ConfigManager.TAG_GROUP) {
      return applicationManager.assignedGroups.containsKey(index);
    }
    if (tag == ConfigManager.TAG_APP) {
      return assignedApps[index] != null ||
          applicationManager.missingApplications.containsKey(index);
    }
    return true;
  }

  Color staticColor(int index) {
    final tag = sliderTags[index];
    final hasMissing =
        applicationManager.missingApplications.containsKey(index);

    switch (tag) {
      case ConfigManager.TAG_DEFAULT_DEVICE:
        return AppTheme.deviceSliderColor;
      case ConfigManager.TAG_MASTER_VOLUME:
        return AppTheme.masterSliderColor;
      case ConfigManager.TAG_ACTIVE_APP:
        return AppTheme.activeSliderColor;
      case ConfigManager.TAG_GROUP:
        return applicationManager.assignedGroups[index]?.color ??
            AppTheme.unassignedSliderColor;
      case ConfigManager.TAG_APP:
        if (assignedApps[index] != null) return AppTheme.appSliderColor;
        if (hasMissing) return AppTheme.missingAppColor;
        return AppTheme.unassignedSliderColor;
      default:
        return AppTheme.unassignedSliderColor;
    }
  }
}
