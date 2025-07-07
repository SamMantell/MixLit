import 'package:flutter/material.dart';
import 'package:mixlit/frontend/menus/dialog/warning.dart';

class ConnectionHandler extends ChangeNotifier {
  bool hasShownInitialDialog = false;
  bool _isCurrentlyConnected = false;
  bool isNotificationInProgress = false;

  bool get isCurrentlyConnected => _isCurrentlyConnected;

  void showConnectionNotification(BuildContext context, bool connected) {
    if (isNotificationInProgress) return;
    if (connected == _isCurrentlyConnected) return;

    isNotificationInProgress = true;
    _isCurrentlyConnected = connected;
    notifyListeners();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              connected ? Icons.usb_rounded : Icons.usb_off_rounded,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Text(connected
                ? "MixLit device connected"
                : "MixLit device disconnected"),
          ],
        ),
        backgroundColor: connected ? Colors.green : Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );

    Future.delayed(const Duration(milliseconds: 500), () {
      isNotificationInProgress = false;
    });
  }

  void initializeDeviceConnection(
      BuildContext context, Future<bool> initialConnectionState) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final isConnected = await initialConnectionState;
      _isCurrentlyConnected = isConnected;
      notifyListeners();

      if (!isConnected && !hasShownInitialDialog) {
        hasShownInitialDialog = true;
        if (context.mounted) {
          FailedToConnectToDeviceDialog.show(context,
              "Couldn't detect your MixLit, app will maintain basic functionality.");
        }
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
  }
}
