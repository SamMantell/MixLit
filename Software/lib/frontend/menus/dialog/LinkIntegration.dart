import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:mixlit/frontend/menus/dialog/integrations/SpotifyIntegration.dart';
import 'package:mixlit/frontend/menus/dialog/integrations/SonosIntegration.dart';

/// Base integration dialog that displays available integrations
class LinkIntegrationDialog extends StatelessWidget {
  final int? sliderIndex;

  const LinkIntegrationDialog({
    super.key,
    this.sliderIndex,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 500,
          constraints: const BoxConstraints(maxHeight: 600),
          decoration: BoxDecoration(
            color:
                isDarkMode ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDarkMode
                  ? Colors.white.withOpacity(0.1)
                  : Colors.black.withOpacity(0.1),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(context, isDarkMode),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: _buildIntegrationsList(context, isDarkMode),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDarkMode
                ? Colors.white.withOpacity(0.1)
                : Colors.black.withOpacity(0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isDarkMode
                  ? Colors.white.withOpacity(0.1)
                  : Colors.black.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.power,
              color: isDarkMode ? Colors.white : Colors.black87,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Link Integration',
                  style: TextStyle(
                    fontFamily: 'BitstreamVeraSans',
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
                if (sliderIndex != null)
                  Text(
                    'Slider ${sliderIndex! + 1}',
                    style: TextStyle(
                      fontFamily: 'BitstreamVeraSans',
                      fontSize: 12,
                      color: isDarkMode ? Colors.white60 : Colors.black54,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.close,
              color: isDarkMode ? Colors.white70 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntegrationsList(BuildContext context, bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select an integration',
          style: TextStyle(
            fontFamily: 'BitstreamVeraSans',
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: isDarkMode ? Colors.white70 : Colors.black54,
          ),
        ),
        const SizedBox(height: 16),

        // Spotify Integration
        _buildIntegrationTile(
          context: context,
          isDarkMode: isDarkMode,
          title: 'Spotify',
          subtitle: 'Control Spotify playback volume',
          icon: Image.asset(
            'lib/frontend/assets/images/logo/integrations/Spotify.png',
            width: 32,
            height: 32,
            fit: BoxFit.contain,
          ),
          color: const Color(0xFF1DB954),
          onTap: () async {
            final result = await showDialog(
              context: context,
              builder: (context) => SpotifyIntegrationDialog(
                sliderIndex: sliderIndex,
              ),
            );

            if (result != null && context.mounted) {
              Navigator.pop(context, result);
            }
          },
        ),

        const SizedBox(height: 12),

        // Sonos Integration
        _buildIntegrationTile(
          context: context,
          isDarkMode: isDarkMode,
          title: 'Sonos',
          subtitle: 'Control Sonos speaker volume',
          icon: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFFD8A158),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.speaker_group,
              color: Colors.white,
              size: 20,
            ),
          ),
          color: const Color(0xFF00B4D8),
          onTap: () async {
            final result = await showDialog(
              context: context,
              builder: (context) => SonosIntegrationDialog(
                sliderIndex: sliderIndex,
              ),
            );

            if (result != null && context.mounted) {
              Navigator.pop(context, result);
            }
          },
        ),
      ],
    );
  }

  Widget _buildIntegrationTile({
    required BuildContext context,
    required bool isDarkMode,
    required String title,
    required String subtitle,
    required Widget icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDarkMode
                ? Colors.white.withOpacity(0.05)
                : Colors.black.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDarkMode
                  ? Colors.white.withOpacity(0.1)
                  : Colors.black.withOpacity(0.1),
            ),
          ),
          child: Row(
            children: [
              icon,
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'BitstreamVeraSans',
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontFamily: 'BitstreamVeraSans',
                        fontSize: 12,
                        color: isDarkMode ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: color,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
