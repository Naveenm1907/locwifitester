import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

/// A banner that shows connection status at the top of screens
class ConnectionStatusBanner extends StatelessWidget {
  const ConnectionStatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        // Don't show banner if connected
        if (appState.isConnected) {
          return const SizedBox.shrink();
        }

        // Show offline banner
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.orange.shade100,
            border: Border(
              bottom: BorderSide(
                color: Colors.orange.shade300,
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.cloud_off,
                color: Colors.orange.shade900,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'No Internet Connection',
                      style: TextStyle(
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    if (appState.lastSuccessfulSync != null)
                      Text(
                        'Using cached data from ${_formatTime(appState.lastSuccessfulSync!)}',
                        style: TextStyle(
                          color: Colors.orange.shade800,
                          fontSize: 11,
                        ),
                      )
                    else
                      Text(
                        'Some features may be limited',
                        style: TextStyle(
                          color: Colors.orange.shade800,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.refresh,
                  color: Colors.orange.shade900,
                  size: 20,
                ),
                onPressed: () async {
                  await appState.checkConnectivity();
                  if (appState.isConnected) {
                    // Refresh data
                    await Future.wait([
                      appState.loadRooms(silent: true),
                      appState.loadWiFiRouters(silent: true),
                    ]);
                  }
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Check connection',
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }
}

/// A loading indicator with timeout message for slow networks
class LoadingWithTimeout extends StatefulWidget {
  final String message;
  final Duration slowThreshold;

  const LoadingWithTimeout({
    super.key,
    this.message = 'Loading...',
    this.slowThreshold = const Duration(seconds: 5),
  });

  @override
  State<LoadingWithTimeout> createState() => _LoadingWithTimeoutState();
}

class _LoadingWithTimeoutState extends State<LoadingWithTimeout> {
  bool _isSlow = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.slowThreshold, () {
      if (mounted) {
        setState(() {
          _isSlow = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            widget.message,
            style: const TextStyle(fontSize: 16),
          ),
          if (_isSlow) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.slow_motion_video,
                    color: Colors.orange.shade700,
                    size: 32,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Taking longer than usual...',
                    style: TextStyle(
                      color: Colors.orange.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Please check your internet connection',
                    style: TextStyle(
                      color: Colors.orange.shade600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

