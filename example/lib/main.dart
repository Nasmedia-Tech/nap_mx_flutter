import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nap_mx_flutter/nap_mx_flutter.dart';

void main() => runApp(const NapMxExampleApp());

class NapMxExampleApp extends StatelessWidget {
  const NapMxExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'nap mx Flutter',
    debugShowCheckedModeBanner: false,
    themeMode: ThemeMode.system,
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.indigo,
      brightness: Brightness.dark,
      useMaterial3: true,
    ),
    home: const DemoHome(),
  );
}

class DemoHome extends StatefulWidget {
  const DemoHome({super.key});

  @override
  State<DemoHome> createState() => _DemoHomeState();
}

class _DemoHomeState extends State<DemoHome> {
  static const _envMediaKey = String.fromEnvironment('NAP_MX_MEDIA_KEY');
  static const _envBanner = String.fromEnvironment('NAP_MX_BANNER_ID');
  static const _envNative = String.fromEnvironment('NAP_MX_NATIVE_ID');
  static const _envInline = String.fromEnvironment('NAP_MX_INLINE_VIDEO_ID');
  static const _envInterstitial = String.fromEnvironment(
    'NAP_MX_INTERSTITIAL_ID',
  );
  static const _envVideo = String.fromEnvironment(
    'NAP_MX_INTERSTITIAL_VIDEO_ID',
  );
  static const _envRewarded = String.fromEnvironment('NAP_MX_REWARDED_ID');

  final _mediaKey = TextEditingController(text: _envMediaKey);
  final _ids = <NapMxAdFormat, TextEditingController>{
    NapMxAdFormat.banner: TextEditingController(text: _envBanner),
    NapMxAdFormat.native: TextEditingController(text: _envNative),
    NapMxAdFormat.inlineVideo: TextEditingController(text: _envInline),
    NapMxAdFormat.interstitial: TextEditingController(text: _envInterstitial),
    NapMxAdFormat.interstitialVideo: TextEditingController(text: _envVideo),
    NapMxAdFormat.rewarded: TextEditingController(text: _envRewarded),
  };
  final _logs = <String>[];
  StreamSubscription<NapMxEvent>? _globalEvents;
  StreamSubscription<NapMxEvent>? _requestEvents;
  NapMxFullscreenAdController? _fullscreen;
  NapMxAdViewController? _viewController;
  NapMxSdkInfo? _sdkInfo;
  NapMxAdFormat _viewFormat = NapMxAdFormat.banner;
  NapMxAdFormat _fullscreenFormat = NapMxAdFormat.interstitial;
  NapMxConsentStatus _gdpr = NapMxConsentStatus.unspecified;
  NapMxConsentStatus _usSale = NapMxConsentStatus.unspecified;
  NapMxConsentStatus _child = NapMxConsentStatus.unspecified;
  bool _busy = false;
  String _status = 'Not initialized';
  int _viewGeneration = 0;

  @override
  void initState() {
    super.initState();
    _globalEvents = NapMx.events.listen(_recordEvent);
  }

  @override
  void dispose() {
    _globalEvents?.cancel();
    _requestEvents?.cancel();
    _fullscreen?.dispose();
    _viewController?.dispose();
    _mediaKey.dispose();
    for (final controller in _ids.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Map<NapMxAdFormat, String> get _configuredIds => <NapMxAdFormat, String>{
    for (final entry in _ids.entries)
      if (entry.value.text.trim().isNotEmpty)
        entry.key: entry.value.text.trim(),
  };

  Future<void> _initialize() async {
    final ids = _configuredIds;
    if (_mediaKey.text.trim().isEmpty || ids.isEmpty) {
      _setStatus(
        'Enter a media key and at least one ad unit ID. Requests are blocked.',
      );
      return;
    }
    await _run('Initialize', () async {
      await NapMx.initialize(
        NapMxConfiguration(
          mediaKey: _mediaKey.text.trim(),
          adUnitIds: ids,
          privacy: NapMxPrivacySettings(
            gdprConsent: _gdpr,
            usSaleConsent: _usSale,
            childDirected: _child,
          ),
          logLevel: NapMxLogLevel.debug,
        ),
      );
      _sdkInfo = await NapMx.getSdkInfo();
      _status = 'Initialized';
    });
  }

  Future<void> _loadFullscreen() async {
    final id = _ids[_fullscreenFormat]!.text.trim();
    if (!_requestAllowed(id)) return;
    await _fullscreen?.dispose();
    await _requestEvents?.cancel();
    final controller = NapMxFullscreenAdController(
      format: _fullscreenFormat,
      adUnitId: id,
    );
    _fullscreen = controller;
    _requestEvents = controller.events.listen((_) => setState(() {}));
    await _run('Load ${_fullscreenFormat.wireName}', controller.load);
  }

  Future<void> _showFullscreen() async {
    final controller = _fullscreen;
    if (controller == null || controller.state != NapMxAdState.loaded) {
      _setStatus('Load this full-screen format successfully before show.');
      return;
    }
    await _run('Show ${controller.format.wireName}', controller.show);
  }

  Future<void> _disposeFullscreen() async {
    await _fullscreen?.dispose();
    _fullscreen = null;
    _setStatus('Full-screen request disposed');
  }

  bool _requestAllowed(String id) {
    if (!NapMx.isInitialized) {
      _setStatus('Initialize first.');
      return false;
    }
    if (id.isEmpty) {
      _setStatus(
        'No official public test ID exists for this format. Enter an assigned test ID.',
      );
      return false;
    }
    return true;
  }

  Future<void> _loadView() async {
    final id = _ids[_viewFormat]!.text.trim();
    if (!_requestAllowed(id)) return;
    final controller = _viewController;
    if (controller == null) {
      _setStatus('Create the native view first.');
      return;
    }
    await _run('Load ${_viewFormat.wireName}', controller.load);
  }

  Future<void> _disposeView() async {
    await _viewController?.dispose();
    _viewController = null;
    setState(() {
      _viewGeneration++;
      _status = 'Native view disposed; a fresh view was created.';
    });
  }

  Future<void> _run(String label, Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = '$label…';
    });
    final watch = Stopwatch()..start();
    try {
      await action();
      if (mounted) {
        _setStatus('$label succeeded (${watch.elapsedMilliseconds} ms)');
      }
    } catch (error) {
      if (mounted) _setStatus('$label failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setStatus(String value) {
    if (mounted) setState(() => _status = value);
    _logs.insert(0, '${DateTime.now().toIso8601String()}  $value');
  }

  void _recordEvent(NapMxEvent event) {
    final error = event.error == null
        ? ''
        : ' error=${event.error!.code}/${event.error!.nativeCode}: ${event.error!.message}';
    final reward = event.reward == null
        ? ''
        : ' tx=${event.reward!.transactionId}';
    final network = event.network == null ? '' : ' network=${event.network}';
    final elapsed = event.elapsedMilliseconds == null
        ? ''
        : ' ${event.elapsedMilliseconds}ms';
    final line =
        '${event.timestamp.toIso8601String()}  ${event.type.name}'
        ' ${event.format?.wireName ?? ''}$network$elapsed$error$reward';
    if (mounted) {
      setState(() {
        _logs.insert(0, line);
        if (_logs.length > 200) _logs.removeRange(200, _logs.length);
      });
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('nap mx Flutter'),
        bottom: const TabBar(
          tabs: [
            Tab(icon: Icon(Icons.ad_units), text: 'Ad demo'),
            Tab(icon: Icon(Icons.tune), text: 'Settings'),
            Tab(icon: Icon(Icons.receipt_long), text: 'Logs & guide'),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          children: [
            _demoTab(context),
            _settingsTab(context),
            _logsTab(context),
          ],
        ),
      ),
    ),
  );

  Widget _demoTab(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _statusCard(context),
      const SizedBox(height: 12),
      Text('Native views', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      DropdownButtonFormField<NapMxAdFormat>(
        initialValue: _viewFormat,
        items: const [
          NapMxAdFormat.banner,
          NapMxAdFormat.native,
          NapMxAdFormat.inlineVideo,
        ].map(_formatItem).toList(),
        onChanged: _busy
            ? null
            : (value) async {
                if (value == null) return;
                await _viewController?.dispose();
                setState(() {
                  _viewController = null;
                  _viewFormat = value;
                  _viewGeneration++;
                });
              },
        decoration: const InputDecoration(
          labelText: 'Format',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 8),
      if (NapMx.isInitialized && _ids[_viewFormat]!.text.trim().isNotEmpty)
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: NapMxAdView(
              key: ValueKey('$_viewFormat-$_viewGeneration'),
              format: _viewFormat,
              adUnitId: _ids[_viewFormat]!.text.trim(),
              onViewCreated: (controller) {
                _viewController = controller;
                controller.events.listen((_) {
                  if (mounted) setState(() {});
                });
              },
            ),
          ),
        )
      else
        const _MissingConfiguration(
          text:
              'Initialize and provide an assigned ID to create the SDK native view.',
        ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: _busy ? null : _loadView,
            icon: const Icon(Icons.download),
            label: const Text('Load'),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _disposeView,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Dispose'),
          ),
        ],
      ),
      const Divider(height: 32),
      Text('Full-screen ads', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      DropdownButtonFormField<NapMxAdFormat>(
        initialValue: _fullscreenFormat,
        items: const [
          NapMxAdFormat.interstitial,
          NapMxAdFormat.interstitialVideo,
          NapMxAdFormat.rewarded,
        ].map(_formatItem).toList(),
        onChanged: _busy
            ? null
            : (value) {
                if (value != null) setState(() => _fullscreenFormat = value);
              },
        decoration: const InputDecoration(
          labelText: 'Format',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 8),
      Text('Request state: ${_fullscreen?.state.name ?? 'idle'}'),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: _busy ? null : _loadFullscreen,
            icon: const Icon(Icons.download),
            label: const Text('Load'),
          ),
          FilledButton.tonalIcon(
            onPressed: _busy || _fullscreen?.state != NapMxAdState.loaded
                ? null
                : _showFullscreen,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Show'),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _disposeFullscreen,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Dispose'),
          ),
        ],
      ),
    ],
  );

  DropdownMenuItem<NapMxAdFormat> _formatItem(NapMxAdFormat value) =>
      DropdownMenuItem(value: value, child: Text(value.wireName));

  Widget _settingsTab(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text(
        'Credentials stay in memory and are never logged.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _mediaKey,
        enabled: !NapMx.isInitialized,
        decoration: const InputDecoration(
          labelText: 'Media key',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      for (final entry in _ids.entries) ...[
        TextField(
          controller: entry.value,
          enabled: !NapMx.isInitialized,
          keyboardType: TextInputType.text,
          decoration: InputDecoration(
            labelText: '${entry.key.wireName} ad unit ID',
            helperText: 'Android accepts String; iOS requires an integer.',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
      ],
      _consentField('GDPR personalized ads', _gdpr, (value) => _gdpr = value),
      _consentField('US sale/share', _usSale, (value) => _usSale = value),
      _consentField(
        'Child directed (COPPA)',
        _child,
        (value) => _child = value,
      ),
      const SizedBox(height: 8),
      FilledButton.icon(
        onPressed: _busy || NapMx.isInitialized ? null : _initialize,
        icon: const Icon(Icons.power_settings_new),
        label: const Text('Initialize once'),
      ),
      const SizedBox(height: 12),
      const _MissingConfiguration(
        text:
            'No public universal test ID is documented. Empty IDs block requests; use IDs assigned by nap mx operations. The sample never clicks ads automatically.',
      ),
    ],
  );

  Widget _consentField(
    String label,
    NapMxConsentStatus value,
    ValueChanged<NapMxConsentStatus> update,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DropdownButtonFormField<NapMxConsentStatus>(
      initialValue: value,
      items: NapMxConsentStatus.values
          .map(
            (status) =>
                DropdownMenuItem(value: status, child: Text(status.name)),
          )
          .toList(),
      onChanged: NapMx.isInitialized
          ? null
          : (next) {
              if (next != null) setState(() => update(next));
            },
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  Widget _logsTab(BuildContext context) => Column(
    children: [
      Padding(padding: const EdgeInsets.all(16), child: _statusCard(context)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(child: Text('Events (${_logs.length})')),
            TextButton(
              onPressed: () => setState(_logs.clear),
              child: const Text('Clear'),
            ),
          ],
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: _logs.isEmpty
            ? const Center(child: Text('SDK events appear here.'))
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _logs.length,
                itemBuilder: (context, index) => SelectableText(
                  _logs[index],
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                ),
              ),
      ),
    ],
  );

  Widget _statusCard(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_status, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('SDK: ${_sdkInfo?.sdkVersion ?? 'unknown / not queried'}'),
          Text(
            'Adapters: ${_sdkInfo?.adapterVersions ?? 'not reported by platform'}',
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    ),
  );
}

class _MissingConfiguration extends StatelessWidget {
  const _MissingConfiguration({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );
}
