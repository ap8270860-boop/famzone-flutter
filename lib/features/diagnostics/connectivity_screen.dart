import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_response.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';

/// Developer-only screen that calls `GET /api/v1/ping`.
///
/// Not reachable from the UI. Point `main.dart` at it temporarily whenever
/// you need to confirm the device can reach the backend.
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
    return Scaffold(
      appBar: AppBar(title: const Text('API connectivity')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              AppConfig.apiBaseUrl,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.lavenderGray,
              ),
            ),
            const SizedBox(height: 24),
            Expanded(child: SingleChildScrollView(child: _result())),
            FilledButton(
              onPressed: _loading ? null : _ping,
              child: Text(_loading ? 'Calling…' : 'Ping the API'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _result() {
    if (_error != null) {
      return Text(_error!, style: const TextStyle(color: AppColors.neonPink));
    }

    final response = _response;
    if (response == null) {
      return const Text(
        'Tap below to call /ping',
        style: TextStyle(color: AppColors.lavenderGray),
      );
    }

    final data = response.dataMap;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          response.message,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.emerald,
          ),
        ),
        const SizedBox(height: 12),
        for (final entry in data.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(
              '${entry.key}: ${entry.value}',
              style: const TextStyle(color: AppColors.softWhite),
            ),
          ),
      ],
    );
  }
}
