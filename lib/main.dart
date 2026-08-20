import 'package:flutter/material.dart';

import 'core/api/api_client.dart';
import 'core/api/api_response.dart';
import 'core/config/app_config.dart';

void main() {
  runApp(const FamZoneApp());
}

class FamZoneApp extends StatelessWidget {
  const FamZoneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FamZone',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF4F46E5),
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF4F46E5),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const ConnectivityScreen(),
    );
  }
}

/// Temporary screen that proves the app can reach the backend.
///
/// Replaced by the real onboarding / login flow once phone-OTP auth is built.
class ConnectivityScreen extends StatefulWidget {
  const ConnectivityScreen({super.key});

  @override
  State<ConnectivityScreen> createState() => _ConnectivityScreenState();
}

class _ConnectivityScreenState extends State<ConnectivityScreen> {
  final _api = ApiClient();

  bool _loading = false;
  ApiResponse? _response;
  String? _error;

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  Future<void> _ping() async {
    setState(() {
      _loading = true;
      _error = null;
      _response = null;
    });

    try {
      final result = await _api.get('ping');
      if (!mounted) return;
      setState(() => _response = result);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('FamZone'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'API connectivity',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                AppConfig.apiBaseUrl,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Expanded(child: _buildResult(theme)),
              FilledButton.icon(
                onPressed: _loading ? null : _ping,
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering),
                label: Text(_loading ? 'Calling…' : 'Ping the API'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResult(ThemeData theme) {
    if (_error != null) {
      return _ResultCard(
        color: theme.colorScheme.errorContainer,
        icon: Icons.error_outline,
        iconColor: theme.colorScheme.error,
        title: 'Could not reach the API',
        body: _error!,
      );
    }

    final response = _response;
    if (response == null) {
      return Center(
        child: Text(
          'Tap below to call /ping',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    if (!response.success) {
      return _ResultCard(
        color: theme.colorScheme.errorContainer,
        icon: Icons.warning_amber_outlined,
        iconColor: theme.colorScheme.error,
        title: 'HTTP ${response.statusCode}',
        body: response.message.isEmpty ? 'Unknown error' : response.message,
      );
    }

    final data = response.dataMap;

    return _ResultCard(
      color: theme.colorScheme.secondaryContainer,
      icon: Icons.check_circle_outline,
      iconColor: Colors.green.shade700,
      title: response.message,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row('App', data['app']),
          _row('Environment', data['environment']),
          _row('API version', data['api_version']),
          _row('Laravel', data['laravel']),
          _row('PHP', data['php']),
          _row('Server time', data['server_time']),
        ],
      ),
    );
  }

  Widget _row(String label, Object? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(value?.toString() ?? '—')),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.color,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.body,
    this.child,
  });

  final Color color;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? body;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (body != null) Text(body!),
            if (child != null) child!,
          ],
        ),
      ),
    );
  }
}
