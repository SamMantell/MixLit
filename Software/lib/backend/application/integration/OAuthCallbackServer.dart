import 'dart:async';
import 'dart:io';

class OAuthCallbackServer {
  final int port;
  HttpServer? _server;

  OAuthCallbackServer({this.port = 8888});

  Future<String?> waitForCallback({String service = 'Spotify'}) async {
    final completer = Completer<String?>();

    try {
      _server = await HttpServer.bind('127.0.0.1', port);
      print('OAuth callback server listening on http://127.0.0.1:$port');

      _server!.listen((request) async {
        final code = request.uri.queryParameters['code'];
        final error = request.uri.queryParameters['error'];

        // Determine color scheme based on service
        final gradient = service == 'Sonos'
            ? 'linear-gradient(135deg, #D8A158 0%, #333333 100%)'
            : 'linear-gradient(135deg, #1DB954 0%, #191414 100%)';

        // Send response to browser
        request.response
          ..statusCode = 200
          ..headers.set('Content-Type', 'text/html; charset=utf-8')
          ..write('''
            <!DOCTYPE html>
            <html>
            <head>
                <title>MixLit - $service Authorization</title>
                <style>
                    body {
                        font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                        background: $gradient;
                        color: white;
                        display: flex;
                        justify-content: center;
                        align-items: center;
                        height: 100vh;
                        margin: 0;
                    }
                    .container {
                        text-align: center;
                        background: rgba(0,0,0,0.3);
                        padding: 40px;
                        border-radius: 16px;
                        box-shadow: 0 8px 32px rgba(0,0,0,0.3);
                    }
                    h1 { margin: 0 0 20px 0; }
                    p { margin: 10px 0; opacity: 0.9; }
                </style>
            </head>
            <body>
                <div class="container">
                    ${error != null ? '''
                        <h1>❌ Authorization Failed</h1>
                        <p>Error: $error</p>
                    ''' : '''
                        <h1>✅ Success!</h1>
                        <p>$service has been linked to MixLit.</p>
                        <p>You can close this window now.</p>
                    '''}
                </div>
            </body>
            </html>
          ''');

        await request.response.close();
        await _server?.close();
        _server = null;

        if (error != null) {
          completer.completeError(Exception('Authorization error: $error'));
        } else {
          completer.complete(code);
        }
      });

      return completer.future;
    } catch (e) {
      print('Error starting OAuth callback server: $e');
      await _server?.close();
      return null;
    }
  }

  Future<void> close() async {
    await _server?.close();
    _server = null;
  }
}
