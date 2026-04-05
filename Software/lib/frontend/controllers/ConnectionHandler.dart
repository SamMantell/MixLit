import 'package:flutter/material.dart';
import 'package:mixlit/frontend/menus/dialog/warning.dart';

class ConnectionHandler extends ChangeNotifier {
  bool hasShownInitialDialog = false;
  bool _isCurrentlyConnected = false;
  bool _isNotificationInProgress = false;

  bool get isCurrentlyConnected => _isCurrentlyConnected;

  void initializeDeviceConnection(BuildContext context, bool isConnected) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isCurrentlyConnected = isConnected;
      notifyListeners();

      if (!isConnected && !hasShownInitialDialog) {
        hasShownInitialDialog = true;
        if (context.mounted) {
          FailedToConnectToDeviceDialog.show(
            context,
            "Couldn't detect a MixLit; app will maintain basic functionality.",
          );
        }
      }
    });
  }

  void showConnectionNotification(BuildContext context, bool connected) {
    if (_isNotificationInProgress) return;
    if (connected == _isCurrentlyConnected) return;

    _isNotificationInProgress = true;
    _isCurrentlyConnected = connected;
    notifyListeners();

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(
          connected ? Icons.usb_rounded : Icons.usb_off_rounded,
          color: Colors.white,
        ),
        const SizedBox(width: 8),
        Text(connected
            ? 'MixLit device connected'
            : 'MixLit device disconnected'),
      ]),
      backgroundColor: connected ? Colors.green : Colors.red,
      duration: const Duration(seconds: 3),
    ));

    Future.delayed(const Duration(milliseconds: 500), () {
      _isNotificationInProgress = false;
    });
  }

  @override
  void dispose() {
    super.dispose();
  }
}
