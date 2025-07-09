import 'dart:async';
import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final DateTime releaseDate;
  final String changelog;
  final String downloadUrl;
  final String fileName;

  UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseDate,
    required this.changelog,
    required this.downloadUrl,
    required this.fileName,
  });
}

class UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;
  final Function(double) onProgressUpdate;
  final Function() onUpdateNow;

  const UpdateDialog({
    super.key,
    required this.updateInfo,
    required this.onProgressUpdate,
    required this.onUpdateNow,
  });

  @override
  _UpdateDialogState createState() => _UpdateDialogState();

  static Future<bool?> show({
    required BuildContext context,
    required UpdateInfo updateInfo,
    required Function(double) onProgressUpdate,
    required Function() onUpdateNow,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return UpdateDialog(
          updateInfo: updateInfo,
          onProgressUpdate: onProgressUpdate,
          onUpdateNow: onUpdateNow,
        );
      },
    );
  }
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  late ConfettiController _confettiController;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 3),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _confettiController.play();
    });
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    final months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];

    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final vanilla = const Color(0xFFF5F0DC);
    final darkGrey = const Color(0xFF282828);
    final accentColor = const Color(0xFF6AAF50);

    return Stack(
      children: [
        Positioned(
          top: (MediaQuery.of(context).size.height * 0.25) - 20,
          left: MediaQuery.of(context).size.width / 2,
          child: ConfettiWidget(
            confettiController: _confettiController,
            blastDirectionality: BlastDirectionality.explosive,
            particleDrag: 0.05,
            emissionFrequency: 0.05,
            numberOfParticles: 20,
            gravity: 0.1,
            shouldLoop: false,
            colors: const [
              Colors.red,
              Colors.orange,
              Colors.yellow,
              Colors.green,
              Colors.blue,
              Colors.indigo
            ],
          ),
        ),

        // Dialog content
        Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Container(
                width: 500,
                margin: const EdgeInsets.only(top: 40),
                padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
                decoration: BoxDecoration(
                  color: darkGrey,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                  border: Border.all(
                    color: vanilla.withOpacity(0.2),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Yippeee! New Update!',
                      style: TextStyle(
                        fontFamily: 'BitstreamVeraSans',
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: vanilla,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: darkGrey.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: vanilla.withOpacity(0.15),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: RichText(
                                  text: TextSpan(
                                    style: TextStyle(
                                      fontFamily: 'BitstreamVeraSans',
                                      fontSize: 14,
                                      color: vanilla.withOpacity(0.9),
                                    ),
                                    children: [
                                      const TextSpan(text: 'Current version: '),
                                      TextSpan(
                                        text: widget.updateInfo.currentVersion,
                                        style: TextStyle(
                                          color: vanilla.withOpacity(0.6),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Expanded(
                                child: RichText(
                                  text: TextSpan(
                                    style: TextStyle(
                                      fontFamily: 'BitstreamVeraSans',
                                      fontSize: 14,
                                      color: vanilla.withOpacity(0.9),
                                    ),
                                    children: [
                                      const TextSpan(text: 'New version: '),
                                      TextSpan(
                                        text: widget.updateInfo.latestVersion,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: accentColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Released on: ${_formatDate(widget.updateInfo.releaseDate)}',
                              style: TextStyle(
                                fontFamily: 'BitstreamVeraSans',
                                fontSize: 12,
                                color: vanilla.withOpacity(0.7),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Changelog:',
                        style: TextStyle(
                          fontFamily: 'BitstreamVeraSans',
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: vanilla,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 120,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: darkGrey.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: vanilla.withOpacity(0.15),
                          width: 1,
                        ),
                      ),
                      child: Markdown(
                        data: widget.updateInfo.changelog,
                        shrinkWrap: true,
                        physics: const BouncingScrollPhysics(),
                        styleSheet: MarkdownStyleSheet(
                          p: TextStyle(
                            fontFamily: 'BitstreamVeraSans',
                            fontSize: 14,
                            color: vanilla.withOpacity(0.9),
                            height: 1.4,
                          ),
                          h1: TextStyle(
                            fontFamily: 'BitstreamVeraSans',
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: vanilla,
                          ),
                          h2: TextStyle(
                            fontFamily: 'BitstreamVeraSans',
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: vanilla,
                          ),
                          h3: TextStyle(
                            fontFamily: 'BitstreamVeraSans',
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: vanilla.withOpacity(0.95),
                          ),
                          h4: TextStyle(
                            fontFamily: 'BitstreamVeraSans',
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: vanilla.withOpacity(0.9),
                          ),
                          h5: TextStyle(
                            fontFamily: 'BitstreamVeraSans',
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: vanilla.withOpacity(0.85),
                          ),
                          h6: TextStyle(
                            fontFamily: 'BitstreamVeraSans',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: vanilla.withOpacity(0.8),
                          ),
                          em: TextStyle(
                            fontFamily: 'BitstreamVeraSans',
                            fontStyle: FontStyle.italic,
                            color: vanilla.withOpacity(0.9),
                          ),
                          strong: TextStyle(
                            fontFamily: 'BitstreamVeraSans',
                            fontWeight: FontWeight.bold,
                            color: vanilla,
                          ),
                          blockquote: TextStyle(
                            fontFamily: 'BitstreamVeraSans',
                            fontStyle: FontStyle.italic,
                            color: vanilla.withOpacity(0.8),
                          ),
                          code: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 14,
                            color: accentColor,
                            backgroundColor: darkGrey.withOpacity(0.7),
                          ),
                          codeblockDecoration: BoxDecoration(
                            color: darkGrey.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          a: TextStyle(
                            fontFamily: 'BitstreamVeraSans',
                            color: accentColor,
                            decoration: TextDecoration.underline,
                          ),
                          listBullet: TextStyle(
                            fontFamily: 'BitstreamVeraSans',
                            color: accentColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_isDownloading)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Downloading: ${(_downloadProgress * 100).toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontFamily: 'BitstreamVeraSans',
                              fontSize: 14,
                              color: accentColor,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            height: 8,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              color: darkGrey.withOpacity(0.5),
                              border: Border.all(
                                color: vanilla.withOpacity(0.15),
                                width: 1,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: _downloadProgress,
                                backgroundColor: Colors.transparent,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(accentColor),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _isDownloading
                              ? null
                              : () => Navigator.of(context).pop(false),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            foregroundColor: vanilla.withOpacity(0.7),
                            disabledForegroundColor: vanilla.withOpacity(0.3),
                          ),
                          child: const Text(
                            'Later',
                            style: TextStyle(
                              fontFamily: 'BitstreamVeraSans',
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton(
                          onPressed: _isDownloading
                              ? null
                              : () async {
                                  setState(() {
                                    _isDownloading = true;
                                  });

                                  Timer.periodic(
                                      const Duration(milliseconds: 100),
                                      (timer) {
                                    if (_downloadProgress < 1.0) {
                                      widget
                                          .onProgressUpdate(_downloadProgress);
                                      setState(() {
                                        _downloadProgress += 0.01;
                                        if (_downloadProgress > 1.0) {
                                          _downloadProgress = 1.0;
                                          timer.cancel();

                                          // Launch the update process
                                          Future.delayed(
                                              const Duration(milliseconds: 500),
                                              () {
                                            widget.onUpdateNow();
                                            Navigator.of(context).pop(true);
                                          });
                                        }
                                      });
                                    } else {
                                      timer.cancel();
                                    }
                                  });
                                },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                            backgroundColor: accentColor,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor:
                                accentColor.withOpacity(0.3),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
                            _isDownloading ? 'Downloading...' : 'Gimme',
                            style: const TextStyle(
                              fontFamily: 'BitstreamVeraSans',
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Positioned(
                top: -20,
                child: Image.asset(
                  'lib/frontend/assets/images/logo/yippeee.png',
                  height: 100,
                  width: 100,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
