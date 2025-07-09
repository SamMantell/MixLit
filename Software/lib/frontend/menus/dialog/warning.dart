import 'dart:ui';
import 'package:flutter/material.dart';

class FailedToConnectToDeviceDialog extends StatelessWidget {
  final String message;
  const FailedToConnectToDeviceDialog({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width * 0.3,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.75),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              const Icon(
                Icons.warning_amber_rounded,
                color: Colors.amber,
                size: 48,
              ),
              const SizedBox(height: 16),
              // Title
              const Text(
                'Warning',
                style: TextStyle(
                  fontFamily: 'BitstreamVeraSans',
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              // Message
              Text(
                message,
                style: const TextStyle(
                  fontFamily: 'BitstreamVeraSans',
                  color: Colors.white,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // alrighty Button
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  backgroundColor: Colors.white.withOpacity(0.1),
                ),
                child: const Text(
                  'alrighty',
                  style: TextStyle(
                    fontFamily: 'BitstreamVeraSans',
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void show(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return FailedToConnectToDeviceDialog(message: message);
      },
    );
  }
}
