import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:mixlit/backend/application/audio/ApplicationManager.dart';
import 'package:mixlit/backend/application/audio/audio_service_client.dart';
import 'package:mixlit/backend/application/data/ConfigManager.dart';
import 'package:mixlit/backend/application/util/IconColourExtractor.dart';
import 'package:mixlit/backend/application/util/IconExtractor.dart';
import 'package:mixlit/frontend/Theme.dart';

class SliderColorHelper {
  final AudioServiceClient audioServiceClient;
  bool audioServiceConnected;

  SliderColorHelper({
    required this.audioServiceClient,
    this.audioServiceConnected = false,
  });

  Future<Uint8List?> loadIcon(
    String processPath,
    Map<String, Uint8List?> appIcons,
  ) async {
    if (appIcons.containsKey(processPath)) return appIcons[processPath];

    if (audioServiceConnected) {
      try {
        final iconBase64 = await audioServiceClient.getIcon(processPath);
        if (iconBase64 != null) {
          final decoded = base64Decode(iconBase64);
          appIcons[processPath] = decoded;
          return decoded;
        }
      } catch (e) {
        print('[SliderColorHelper] Service icon error for $processPath: $e');
      }
    }

    final local = await _extractLocalIcon(processPath);
    appIcons[processPath] = local;
    return local;
  }

  Future<Uint8List?> _extractLocalIcon(String processPath) async {
    try {
      if (Platform.isWindows && await File(processPath).exists()) {
        return await IconExtractor.extractSmallIcon(processPath);
      }
    } catch (e) {
      print('[SliderColorHelper] Local icon extraction error: $e');
    }
    return null;
  }

  /// Reads a previously-cached `.ico` file from disk.
  Future<Uint8List?> loadCachedIcon(String cachedIconPath) async {
    try {
      final file = File(cachedIconPath);
      if (await file.exists()) return await file.readAsBytes();
    } catch (e) {
      print('[SliderColorHelper] Cached icon read error: $e');
    }
    return null;
  }

  Future<Map<int, Color>> resolveAllColors({
    required ApplicationManager applicationManager,
    required List<AudioSessionInfo?> assignedApps,
    required List<String> sliderTags,
    required Map<String, Uint8List?> appIcons,
    required Map<String, Uint8List?> cachedAppIcons,
  }) async {
    final colors = <int, Color>{};
    for (int i = 0; i < assignedApps.length; i++) {
      colors[i] = await resolveColor(
        index: i,
        applicationManager: applicationManager,
        assignedApps: assignedApps,
        sliderTags: sliderTags,
        appIcons: appIcons,
        cachedAppIcons: cachedAppIcons,
      );
    }
    return colors;
  }

  Future<Color> resolveColor({
    required int index,
    required ApplicationManager applicationManager,
    required List<AudioSessionInfo?> assignedApps,
    required List<String> sliderTags,
    required Map<String, Uint8List?> appIcons,
    required Map<String, Uint8List?> cachedAppIcons,
  }) async {
    final tag = sliderTags[index];
    final app = assignedApps[index];

    switch (tag) {
      case ConfigManager.TAG_INTEGRATION:
        final integration = applicationManager.assignedIntegrations[index];
        if (integration == null) return AppTheme.defaultAppColor;
        return switch (integration['type']) {
          'spotify' => const Color(0xFF1DB954),
          'sonos' => const Color(0xFFD8A158),
          _ => AppTheme.defaultAppColor,
        };

      case ConfigManager.TAG_DEFAULT_DEVICE:
        return AppTheme.deviceVolumeColor;

      case ConfigManager.TAG_MASTER_VOLUME:
        return AppTheme.masterVolumeColor;

      case ConfigManager.TAG_ACTIVE_APP:
        return AppTheme.activeAppColor;

      case ConfigManager.TAG_UNASSIGNED:
        return AppTheme.unassignedColor;

      case ConfigManager.TAG_GROUP:
        return applicationManager.assignedGroups[index]?.color ??
            AppTheme.defaultAppColor;

      case ConfigManager.TAG_APP:
        if (app != null) {
          final iconData = await loadIcon(app.processPath, appIcons);
          if (iconData != null) {
            return await IconColorExtractor.extractDominantColor(
              iconData,
              app.processPath,
              defaultColor: AppTheme.defaultAppColor,
            );
          }
          return AppTheme.defaultAppColor;
        }

        final missing = applicationManager.missingApplications[index];
        if (missing != null) {
          if (missing.cachedIconPath != null) {
            final cached = await loadCachedIcon(missing.cachedIconPath!);
            if (cached != null) {
              cachedAppIcons[missing.processName] = cached;
              return await IconColorExtractor.extractDominantColor(
                cached,
                missing.processName,
                defaultColor: AppTheme.missingAppColor,
              );
            }
          }
          return AppTheme.missingAppColor;
        }
        return AppTheme.defaultAppColor;

      default:
        return AppTheme.defaultAppColor;
    }
  }
}
