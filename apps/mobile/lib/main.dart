import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'design_system.dart';
import 'services/image_pipeline.dart';
import 'services/mock_frame.dart';
import 'services/pairing.dart';
import 'services/frame_wifi_transport_stub.dart'
    if (dart.library.io) 'services/frame_wifi_transport_io.dart' as physical;
import 'services/photo_store_web.dart'
    if (dart.library.io) 'services/photo_store_io.dart' as photo;

void main() => runApp(const LumairieApp());

class LumairieApp extends StatefulWidget {
  const LumairieApp({super.key, this.initialPage = 0});
  final int initialPage;
  @override
  State<LumairieApp> createState() => _LumairieAppState();
}

class _LumairieAppState extends State<LumairieApp> {
  bool dark = false;
  bool demo = true;
  int page = 0;
  int activeTab = 0;
  int selectedPhoto = 0;
  int orientation = 0;
  int fit = 0;
  double focalX = .5;
  double focalY = .5;
  int quarterTurns = 0;
  int hubMode = 0;
  int widgetFilter = 0;
  final enabledWidgets = <String>{'Calendar', 'Weather', 'To-do'};
  final addedWidgets = <String>{};
  final photos = <photo.PhotoRecord>[];
  double sendProgress = 0;
  String sendStatus = '';
  bool sending = false;
  bool pairingBusy = false;
  final MockFrame mockFrame = MockFrame();
  final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  bool simWifiConnected = true;
  int simFault = 0;
  String simState = 'Standby';
  String simStatus = 'Waiting for a photo';
  Uint8List? simPreview;
  String? pairedName;
  String? pairedId;
  String? pairingError;
  bool wifiProvisionBusy = false;
  bool wifiProvisionedHere = false;

  @override
  void initState() {
    super.initState();
    page = widget.initialPage;
    activeTab = page == 3
        ? 1
        : page == 4
            ? 2
            : 0;
    if (page == 7) orientation = 1;
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPhotos = await photo.loadPhotos();
    if (!mounted) return;
    setState(() {
      dark = prefs.getBool('dark') ?? false;
      demo = prefs.getBool('demo') ?? true;
      pairedName = prefs.getString('pairedName');
      pairedId = prefs.getString('pairedId');
      photos.addAll(savedPhotos);
      hubMode = prefs.getInt('hubMode') ?? 0;
      if (prefs.containsKey('enabledWidgets')) {
        enabledWidgets
          ..clear()
          ..addAll(prefs.getStringList('enabledWidgets') ?? []);
      }
      addedWidgets.addAll(prefs.getStringList('addedWidgets') ?? []);
    });
  }

  void _go(int next, {int? tab}) => setState(() {
        page = next;
        if (tab != null) activeTab = tab;
      });

  Future<void> _saveWidgets() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('enabledWidgets', enabledWidgets.toList());
    await prefs.setStringList('addedWidgets', addedWidgets.toList());
    await prefs.setInt('hubMode', hubMode);
  }

  Future<void> _pick() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 100);
    if (picked == null) return;
    final record = await photo.savePhoto(await picked.readAsBytes());
    photos.insert(0, record);
    if (mounted) {
      setState(() {
        selectedPhoto = 0;
        page = 2;
      });
    }
  }

  Future<void> _send() async {
    if (!demo && pairedId == null) {
      _notice('Pair a physical frame before sending.');
      return;
    }
    if (!demo && photos.isEmpty) {
      _notice('Choose a photo before sending to the physical frame.');
      return;
    }
    if (demo && kIsWeb && !simWifiConnected) {
      setState(() {
        simState = 'Disconnected';
        simStatus = 'Wi-Fi is disconnected. The previous image is unchanged.';
      });
      _notice(simStatus);
      return;
    }
    setState(() {
      sending = true;
      sendProgress = 0;
      sendStatus = 'Preparing photo';
      simState = 'Waking';
      simStatus = 'Preparing image locally';
    });
    try {
      final bytes = photos.isNotEmpty && selectedPhoto < photos.length
          ? await photos[selectedPhoto].bytes()
          : null;
      final packed = bytes == null
          ? ImagePipeline.demoFrame(landscape: orientation == 1)
          : ImagePipeline.process(bytes,
              landscape: orientation == 1,
              fill: fit == 0,
              focalX: focalX,
              focalY: focalY,
              quarterTurns: quarterTurns);
      if (!mounted) return;
      setState(() {
        simState = 'Transferring';
        simStatus = 'Sending packed pixels';
      });
      void updateProgress(double fraction, String status) {
        if (mounted) {
          setState(() {
            sendProgress = fraction;
            sendStatus = status;
            simStatus = status;
            if (fraction >= .96) simState = 'Refreshing';
          });
        }
      }

      if (demo) {
        await mockFrame.transfer(packed,
            dropAckOnceAt: kIsWeb && simFault == 1 ? 0 : null,
            corruptChunkAt: kIsWeb && simFault == 2 ? 0 : null,
            interruptAt: kIsWeb && simFault == 3 ? 256 : null,
            onProgress: updateProgress);
      } else {
        final qr = await PairingService().loadPairedCredential(pairedId!);
        await physical.FrameWifiTransport().send(
          packed,
          qr,
          onProgress: updateProgress,
        );
      }
      if (!mounted) return;
      if (demo) {
        final preview = ImagePipeline.previewPng(mockFrame.visibleFrame!);
        if (!mounted) return;
        setState(() {
          simPreview = preview;
          simState = 'Standby';
          simStatus = 'Demo display refreshed';
        });
        _notice('Demo frame refreshed. Image verified before display.');
      } else {
        setState(() {
          simState = 'Standby';
          simStatus = 'Frame verified image transfer';
          sendProgress = 1;
          sendStatus = 'Image delivered to frame';
        });
        _notice(
            'Image delivered and verified. Display refresh is not yet available on this hardware.');
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          simState = 'Error';
          simStatus = '$error · previous image retained';
        });
      }
      if (mounted) _notice('Transfer failed: $error');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _scanAndPair() async {
    if (kIsWeb) {
      _notice('Use the Android or iOS app to pair a physical frame.');
      return;
    }
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => ScanQrPage(dark: dark)),
    );
    if (raw == null || !mounted) return;
    setState(() {
      pairingBusy = true;
      pairingError = null;
    });
    try {
      final qr = PairingCredential.parse(raw);
      await PairingService().pair(qr);
      if (!mounted) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pairedName', qr.name);
      await prefs.setString('pairedId', qr.id);
      await prefs.setBool('demo', false);
      setState(() {
        pairedName = qr.name;
        pairedId = qr.id;
        pairingBusy = false;
        demo = false;
      });
      _notice('Frame authenticated and stored on this phone.');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        pairingBusy = false;
        pairingError = error.toString();
      });
    }
  }

  /// Uses the existing pairing screen and Espressif Security 2 session.
  /// No credentials are saved in preferences or sent to a backend.
  Future<void> _configurePairedWifi() async {
    final id = pairedId;
    if (id == null || wifiProvisionBusy) return;
    final ssidController = TextEditingController();
    final passwordController = TextEditingController();
    final values = await showDialog<List<String>>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Connect frame to Wi-Fi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ssidController,
              decoration:
                  const InputDecoration(labelText: 'Wi-Fi network (SSID)'),
            ),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Wi-Fi password'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(
                dialog, [ssidController.text, passwordController.text]),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
    ssidController.dispose();
    passwordController.dispose();
    if (values == null || !mounted) return;
    setState(() => wifiProvisionBusy = true);
    try {
      await PairingService().provisionStoredWifi(id, values[0], values[1]);
      if (!mounted) return;
      setState(() => wifiProvisionedHere = true);
      _notice('Frame confirmed connection to Wi-Fi.');
    } catch (error) {
      if (!mounted) return;
      _notice('Wi-Fi provisioning failed: $error');
    } finally {
      if (mounted) setState(() => wifiProvisionBusy = false);
    }
  }

  void _notice(String value) =>
      messengerKey.currentState?.showSnackBar(SnackBar(content: Text(value)));

  @override
  Widget build(BuildContext context) {
    final p = Palette(dark);
    return MaterialApp(
      scaffoldMessengerKey: messengerKey,
      debugShowCheckedModeBanner: false,
      title: 'Lumairie',
      theme: ThemeData(
          useMaterial3: false,
          brightness: dark ? Brightness.dark : Brightness.light,
          scaffoldBackgroundColor: p.background,
          fontFamily: 'LumairieSans',
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent),
      home: Scaffold(
        backgroundColor: p.background,
        body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
          Widget phone = ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Column(children: [
              Expanded(child: _page(p)),
              if ({0, 3, 4}.contains(page)) _nav(p),
            ]),
          );
          if (kIsWeb && constraints.maxWidth >= 820) {
            return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              SizedBox(width: 430, child: phone),
              const SizedBox(width: 28),
              SizedBox(width: 340, child: _simPanel(p)),
            ]);
          }
          return Center(child: phone);
        })),
      ),
    );
  }

  Widget _simPanel(Palette p) =>
      ListView(padding: const EdgeInsets.all(18), children: [
        Text('LOCAL SIMULATOR',
            style: TextStyle(
                color: p.muted,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 2)),
        const SizedBox(height: 12),
        Text('Fake ESP32-C3 · Spectra 6', style: Design.title(p, size: 19)),
        const SizedBox(height: 8),
        Text('State: $simState', style: Design.body(p)),
        Text(simStatus, style: Design.caption(p, muted: true)),
        const SizedBox(height: 18),
        Surface(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('FAKE FRAME DISPLAY', style: Design.caption(p, muted: true)),
          const SizedBox(height: 10),
          AspectRatio(
              aspectRatio: 800 / 480,
              child: Container(
                padding: const EdgeInsets.all(12),
                color: const Color(0xFF3A3029),
                child: Container(
                    color: const Color(0xFFFAF7ED),
                    child: simPreview == null
                        ? Center(
                            child: Text('No image displayed',
                                style: Design.caption(Palette(false),
                                    muted: true)))
                        : Image.memory(simPreview!, fit: BoxFit.contain)),
              )),
          const SizedBox(height: 8),
          Text('Six-color output from the shared Flutter codec',
              style: Design.caption(p, muted: true)),
        ])),
        const SizedBox(height: 17),
        Row(children: [
          Icon(simWifiConnected ? Icons.wifi : Icons.wifi_off,
              size: 18, color: p.foreground),
          const SizedBox(width: 8),
          Text(simWifiConnected ? 'Wi-Fi connected' : 'Wi-Fi disconnected',
              style: Design.body(p))
        ]),
        const SizedBox(height: 10),
        PrimaryButton(
            label: simWifiConnected ? 'Disconnect Wi-Fi' : 'Connect Wi-Fi',
            outline: true,
            onTap: () => setState(() {
                  simWifiConnected = !simWifiConnected;
                  simState = simWifiConnected ? 'Standby' : 'Disconnected';
                  simStatus = simWifiConnected
                      ? 'Local Wi-Fi standby'
                      : 'Previous image remains visible';
                })),
        const SizedBox(height: 20),
        Text('Next transfer', style: Design.caption(p, muted: true)),
        const SizedBox(height: 9),
        Wrap(spacing: 6, runSpacing: 7, children: [
          for (var i = 0; i < 4; i++)
            ChoicePill(
                label: ['Normal', 'Drop ACK', 'Corrupt', 'Interrupt'][i],
                selected: simFault == i,
                compact: true,
                onTap: () => setState(() => simFault = i))
        ]),
        const SizedBox(height: 14),
        PrimaryButton(label: 'Choose a photo', onTap: _pick),
        const SizedBox(height: 9),
        Text(
            'Use the phone preview’s Send button to test transfer and refresh.',
            style: Design.caption(p, muted: true)),
      ]);

  Widget _page(Palette p) {
    switch (page) {
      case 0:
        return _home(p);
      case 1:
        return _gallery(p);
      case 2:
        return _preview(p, false);
      case 3:
        return _hub(p);
      case 4:
        return _profile(p);
      case 5:
        return _connecting(p);
      case 6:
        return _addWidget(p);
      case 7:
        return _preview(p, true);
      default:
        return _home(p);
    }
  }

  Widget _scroll(Palette p, List<Widget> children, {Widget? bottom}) =>
      Column(children: [
        Expanded(
            child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
                children: children)),
        if (bottom != null)
          Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 12), child: bottom),
      ]);

  Widget _brand(Palette p) => Row(children: [
        Icon(Icons.crop_square_outlined, size: 19, color: p.foreground),
        const SizedBox(width: 6),
        Text(brandName,
            style: TextStyle(
                color: p.foreground,
                fontFamily: 'LumairieSans',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.5)),
        const Spacer(),
        GestureDetector(
            onTap: () => _go(4, tab: 2),
            child: Icon(Icons.more_horiz, color: p.foreground, size: 21)),
      ]);

  Widget _back(Palette p, String title, int destination) => GestureDetector(
        onTap: () => _go(destination),
        child: Row(children: [
          Icon(Icons.chevron_left, color: p.foreground, size: 21),
          const SizedBox(width: 2),
          Text(title, style: Design.caption(p))
        ]),
      );

  Widget _nav(Palette p) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 16),
        child: Container(
          height: 54,
          decoration: BoxDecoration(
              color: p.button, borderRadius: BorderRadius.circular(32)),
          child: Row(children: [
            _navItem(p, 0, Icons.home_outlined, 'Home'),
            _navItem(p, 1, Icons.grid_view_rounded, 'Hub'),
            _navItem(p, 2, Icons.person_outline_rounded, 'Profile'),
          ]),
        ),
      );

  Widget _navItem(Palette p, int index, IconData icon, String label) {
    final selected = activeTab == index;
    return Expanded(
        child: GestureDetector(
      onTap: () => _go(
          index == 0
              ? 0
              : index == 1
                  ? 3
                  : 4,
          tab: index),
      child: Container(
        margin: const EdgeInsets.all(5),
        decoration: BoxDecoration(
            color: selected ? p.background : Colors.transparent,
            borderRadius: BorderRadius.circular(28)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 17, color: selected ? p.foreground : p.onButton),
          if (selected) ...[
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    color: p.foreground,
                    fontSize: 11,
                    fontWeight: FontWeight.w700))
          ],
        ]),
      ),
    ));
  }

  Widget _home(Palette p) => _scroll(p, [
        _brand(p),
        const SizedBox(height: 24),
        Text('Home', style: Design.title(p)),
        const SizedBox(height: 16),
        GestureDetector(
            onTap: () => _go(3, tab: 1),
            child: Surface(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  _dashboardArt(p, height: 150),
                  const SizedBox(height: 10),
                  Row(children: [
                    Text('Hub', style: Design.body(p, size: 13)),
                    const SizedBox(width: 5),
                    Text('7.3” home dashboard',
                        style: Design.caption(p, muted: true)),
                    const Spacer(),
                    _badge(p, demo ? 'Demo' : 'Offline')
                  ]),
                ]))),
        const SizedBox(height: 12),
        if (demo)
          Row(children: [
            Expanded(
                child: _deviceCard(p, 'Living room', 0, false, () => _go(1))),
            const SizedBox(width: 10),
            Expanded(
                child: _deviceCard(p, 'Hallway', 1, true, () {
              orientation = 1;
              _go(7);
            })),
          ]),
        if (!demo && pairedName != null)
          Surface(
              child: Row(children: [
            Icon(Icons.crop_square, color: p.foreground),
            const SizedBox(width: 8),
            Text(pairedName!, style: Design.body(p))
          ])),
        if (!demo && pairedName == null)
          Text('No frames paired on this phone',
              style: Design.caption(p, muted: true)),
        const SizedBox(height: 14),
        DashedAdd(label: 'Add device', onTap: () => _go(5)),
        if (demo) ...[
          const SizedBox(height: 10),
          Text('DEMO MODE · Sample frames are simulated',
              style: Design.caption(p, muted: true))
        ],
      ]);

  Widget _badge(Palette p, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
            color: p.foreground, borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            style: TextStyle(
                color: p.background, fontSize: 9, fontWeight: FontWeight.bold)),
      );

  Widget _deviceCard(Palette p, String name, int kind, bool landscape,
          VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Surface(
              padding: const EdgeInsets.all(9),
              child: SizedBox(
                  height: 145,
                  child: Center(
                      child: FrameArt(
                          kind: kind, landscape: landscape, padding: 8)))),
          const SizedBox(height: 7),
          Text(name, style: Design.body(p, size: 12)),
          const SizedBox(height: 3),
          Text(
              '${landscape ? '10”' : '13”'} frame · ${landscape ? 'landscape' : 'portrait'}',
              style: Design.caption(p, muted: true)),
        ]),
      );

  Widget _gallery(Palette p) => _scroll(
      p,
      [
        _back(p, 'Home', 0),
        const SizedBox(height: 23),
        Text('Living room', style: Design.title(p)),
        Text('13” frame', style: Design.caption(p, muted: true)),
        const SizedBox(height: 18),
        Surface(
            child: Row(children: [
          SizedBox(width: 55, height: 43, child: FrameArt(kind: 0, padding: 2)),
          const SizedBox(width: 11),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Now showing', style: Design.caption(p, muted: true)),
            const SizedBox(height: 3),
            Text('Gallery', style: Design.body(p, size: 13))
          ])
        ])),
        const SizedBox(height: 22),
        Text('Send a photo', style: Design.caption(p)),
        const SizedBox(height: 9),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: .82),
          itemCount: (demo ? 6 : 0) + photos.length + 1,
          itemBuilder: (context, i) {
            final count = photos.length + (demo ? 6 : 0);
            if (i == count) {
              return DashedAdd(label: 'Add photos', height: 100, onTap: _pick);
            }
            final photoIndex = i;
            return GestureDetector(
                onTap: () => setState(() => selectedPhoto = photoIndex),
                child: Stack(fit: StackFit.expand, children: [
                  ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: i < photos.length
                          ? Image(image: photos[i].provider, fit: BoxFit.cover)
                          : CustomPaint(
                              painter: ThumbnailPainter(i - photos.length))),
                  if (selectedPhoto == i)
                    Positioned.fill(
                        child: Container(
                            decoration: BoxDecoration(
                                border:
                                    Border.all(color: p.foreground, width: 2),
                                borderRadius: BorderRadius.circular(7)))),
                  if (selectedPhoto == i)
                    Positioned(
                        right: 4,
                        top: 4,
                        child: Icon(Icons.check_circle,
                            size: 17, color: p.foreground)),
                ]));
          },
        ),
      ],
      bottom: PrimaryButton(
          label: 'Preview',
          onTap: () {
            orientation = 0;
            _go(2);
          }));

  Widget _preview(Palette p, bool hallway) => _scroll(
      p,
      [
        _back(p, 'Preview', hallway ? 0 : 1),
        const SizedBox(height: 21),
        Text('Sending to', style: Design.caption(p, muted: true)),
        const SizedBox(height: 4),
        Text(
            !demo
                ? '${pairedName ?? 'LUMAIRIE'} · 7.3”'
                : hallway
                    ? 'Hallway · 10”'
                    : 'Living room · 13”',
            style: Design.title(p, size: 21)),
        const SizedBox(height: 16),
        Surface(
            padding: const EdgeInsets.symmetric(horizontal: 35, vertical: 20),
            child: SizedBox(
              height: 258,
              child: Center(
                  child: GestureDetector(
                onPanUpdate: photos.isEmpty
                    ? null
                    : (details) => setState(() {
                          focalX =
                              (focalX + details.delta.dx / 300).clamp(0, 1);
                          focalY =
                              (focalY + details.delta.dy / 258).clamp(0, 1);
                        }),
                child: FrameArt(
                  kind: hallway ? 1 : 0,
                  landscape: orientation == 1,
                  image: photos.isNotEmpty && selectedPhoto < photos.length
                      ? photos[selectedPhoto].provider
                      : null,
                  alignment: Alignment(focalX * 2 - 1, focalY * 2 - 1),
                  fit: fit == 0 ? BoxFit.cover : BoxFit.contain,
                  quarterTurns: quarterTurns,
                ),
              )),
            )),
        const SizedBox(height: 18),
        _settingRow(p, 'Orientation', ['Portrait', 'Landscape'], orientation,
            (i) => setState(() => orientation = i)),
        const SizedBox(height: 12),
        _settingRow(
            p, 'Fit', ['Fill', 'Fit'], fit, (i) => setState(() => fit = i)),
        if (photos.isNotEmpty)
          TextButton.icon(
            onPressed: () =>
                setState(() => quarterTurns = (quarterTurns + 1) % 4),
            icon: Icon(Icons.rotate_right, size: 17, color: p.foreground),
            label: Text('Rotate · drag to reframe', style: Design.caption(p)),
          ),
        const SizedBox(height: 20),
        Text('Refreshes once, then holds without power.',
            style: Design.caption(p, muted: true)),
        if (sending) ...[
          const SizedBox(height: 16),
          LinearProgressIndicator(
              value: sendProgress,
              color: p.foreground,
              backgroundColor: p.surface),
          const SizedBox(height: 5),
          Text(sendStatus, style: Design.caption(p))
        ],
      ],
      bottom: Column(children: [
        PrimaryButton(
            label: sending
                ? 'Sending…'
                : !demo
                    ? 'Send to LUMAIRIE frame'
                    : 'Send to ${hallway ? 'Hallway' : 'Living room'}',
            onTap: sending ? null : _send),
        const SizedBox(height: 10),
        TextButton(
            onPressed: _pick,
            child: Text('Choose another photo', style: Design.caption(p))),
      ]));

  Widget _settingRow(Palette p, String label, List<String> values, int selected,
          ValueChanged<int> onTap) =>
      Row(children: [
        SizedBox(
            width: 96,
            child: Text(label, style: Design.caption(p, muted: true))),
        for (var i = 0; i < values.length; i++) ...[
          ChoicePill(
              label: values[i],
              selected: selected == i,
              compact: true,
              onTap: () => onTap(i)),
          const SizedBox(width: 6)
        ],
      ]);

  Widget _hub(Palette p) => _scroll(p, [
        _brand(p),
        const SizedBox(height: 25),
        Text('Kitchen', style: Design.title(p)),
        Text('7.3” home dashboard', style: Design.caption(p, muted: true)),
        const SizedBox(height: 15),
        _dashboardArt(p, height: 178),
        const SizedBox(height: 20),
        Text('Layout', style: Design.caption(p, muted: true)),
        const SizedBox(height: 8),
        Row(children: [
          for (var i = 0; i < 3; i++) ...[
            ChoicePill(
                label: ['Day', 'Week', 'Focus'][i],
                selected: hubMode == i,
                compact: true,
                onTap: () {
                  setState(() => hubMode = i);
                  _saveWidgets();
                }),
            const SizedBox(width: 6)
          ]
        ]),
        const SizedBox(height: 19),
        Text('On your dashboard', style: Design.caption(p, muted: true)),
        const SizedBox(height: 5),
        for (final title in ['Calendar', 'Weather', 'To-do'])
          _toggleRow(p, title),
        const SizedBox(height: 12),
        DashedAdd(label: 'Add widget', onTap: () => _go(6)),
        if (demo) ...[
          const SizedBox(height: 11),
          Text('DEMO DATA · Weather is illustrative',
              style: Design.caption(p, muted: true))
        ],
      ]);

  Widget _dashboardArt(Palette p, {required double height}) => Surface(
        padding: const EdgeInsets.all(12),
        child: Container(
          height: height,
          padding: const EdgeInsets.all(9),
          color: const Color(0xFF322922),
          child: Container(
              padding: const EdgeInsets.all(9),
              color: const Color(0xFFF8F4E9),
              child: Row(children: [
                Expanded(
                    flex: 4,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              hubMode == 1
                                  ? 'This week'
                                  : demo
                                      ? 'Thursday'
                                      : const [
                                          'Monday',
                                          'Tuesday',
                                          'Wednesday',
                                          'Thursday',
                                          'Friday',
                                          'Saturday',
                                          'Sunday'
                                        ][DateTime.now().weekday - 1],
                              style: TextStyle(
                                  color: Color(0xFF9A5A39), fontSize: 10)),
                          Text(
                              hubMode == 1
                                  ? (demo ? '43' : '—')
                                  : (demo ? '22' : '${DateTime.now().day}'),
                              style: TextStyle(
                                  color: Color(0xFF402B25),
                                  fontSize: 35,
                                  height: 1)),
                          Text(
                              demo
                                  ? 'October'
                                  : const [
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
                                    ][DateTime.now().month - 1],
                              style: TextStyle(
                                  color: Color(0xFF54443A), fontSize: 10)),
                        ])),
                Expanded(
                    flex: 5,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                              padding: const EdgeInsets.all(6),
                              color: const Color(0xFFECE6D8),
                              child: Text(
                                  demo && enabledWidgets.contains('Weather')
                                      ? '[18°]\n[Weather]'
                                      : 'No local weather',
                                  style: TextStyle(
                                      color: Color(0xFF503D2F), fontSize: 11))),
                          const SizedBox(height: 6),
                          Text(
                              demo
                                  ? '${enabledWidgets.contains('Calendar') ? '•  [Event]' : ''}\n${enabledWidgets.contains('To-do') ? '•  [To-do]' : ''}'
                                  : 'Add local data',
                              style: TextStyle(
                                  color: Color(0xFF714F3F), fontSize: 10)),
                        ])),
              ])),
        ),
      );

  Widget _toggleRow(Palette p, String title) => Container(
        height: 44,
        decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: p.stroke, width: .6))),
        child: Row(children: [
          Text(title, style: Design.body(p, size: 12)),
          const Spacer(),
          Switch.adaptive(
              value: enabledWidgets.contains(title),
              activeThumbColor: p.foreground,
              onChanged: (v) {
                setState(() => v
                    ? enabledWidgets.add(title)
                    : enabledWidgets.remove(title));
                _saveWidgets();
              })
        ]),
      );

  Widget _profile(Palette p) => _scroll(p, [
        _brand(p),
        const SizedBox(height: 25),
        Text('Profile', style: Design.title(p)),
        const SizedBox(height: 16),
        Surface(
            child: Row(children: [
          CircleAvatar(
              backgroundColor: p.surface2,
              child: Icon(Icons.phone_iphone, color: p.foreground)),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Local settings', style: Design.body(p, size: 13)),
            Text('This phone · No account',
                style: Design.caption(p, muted: true))
          ])
        ])),
        const SizedBox(height: 22),
        Text('Appearance', style: Design.caption(p, muted: true)),
        _profileRow(p, 'Dark mode',
            trailing: Switch.adaptive(
                value: dark,
                onChanged: (v) async {
                  setState(() => dark = v);
                  (await SharedPreferences.getInstance()).setBool('dark', v);
                })),
        _profileRow(p, 'Demo Mode',
            trailing: Switch.adaptive(
                value: demo,
                onChanged: (v) async {
                  setState(() => demo = v);
                  (await SharedPreferences.getInstance()).setBool('demo', v);
                })),
        const SizedBox(height: 20),
        Text('Devices', style: Design.caption(p, muted: true)),
        _profileRow(p, 'Add a frame', onTap: () => _go(5)),
        _profileRow(p, 'Local network',
            onTap: () => _notice(
                'BLE pairing works without Wi-Fi. Local Wi-Fi is optional.')),
        const SizedBox(height: 20),
        Text('About', style: Design.caption(p, muted: true)),
        _profileRow(p, 'Privacy',
            onTap: () => _notice('Photos and settings stay on this phone.')),
        _profileRow(p, 'Help and support',
            onTap: () => _notice(
                'Keep your QR card and wake the frame before pairing.')),
      ]);

  Widget _profileRow(Palette p, String title,
          {Widget? trailing, VoidCallback? onTap}) =>
      InkWell(
        onTap: onTap,
        child: Container(
            height: 48,
            decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: p.stroke, width: .6))),
            child: Row(children: [
              Text(title, style: Design.body(p, size: 12)),
              const Spacer(),
              trailing ?? Icon(Icons.chevron_right, size: 17, color: p.muted)
            ])),
      );

  Widget _connecting(Palette p) => _scroll(
      p,
      [
        _back(p, 'Add device', 0),
        const SizedBox(height: 85),
        _deviceIllustration(p),
        const SizedBox(height: 31),
        Center(
            child: Text('Connecting your frame',
                style: Design.title(p, size: 19))),
        const SizedBox(height: 5),
        Center(
            child: Text('Keep it close to your phone',
                style: Design.caption(p, muted: true))),
        const SizedBox(height: 35),
        _step(p, demo || pairedName != null, 'Frame found',
            demo ? 'Demo frame' : pairedName ?? 'Scan QR to find frame'),
        _step(
            p,
            wifiProvisionedHere,
            'Joining Wi-Fi',
            wifiProvisionedHere
                ? 'Connected successfully'
                : 'Connect after scanning the frame QR'),
        _step(p, false, 'Syncing your display',
            'Requires physical pairing window'),
        const SizedBox(height: 24),
        if (pairingError != null)
          Text(pairingError!,
              style: TextStyle(color: p.foreground, fontSize: 11)),
        if (!demo && pairedId != null) ...[
          PrimaryButton(
              label: wifiProvisionBusy
                  ? 'Connecting to Wi-Fi…'
                  : 'Connect to Wi-Fi',
              onTap: wifiProvisionBusy ? null : _configurePairedWifi),
          const SizedBox(height: 12),
        ],
        if (demo) ...[
          const SizedBox(height: 12),
          PrimaryButton(
              label: 'Open demo frame', outline: true, onTap: () => _go(1)),
        ],
      ],
      bottom: Column(mainAxisSize: MainAxisSize.min, children: [
        PrimaryButton(
            label: pairingBusy ? 'Authenticating…' : 'Scan frame QR code',
            onTap: pairingBusy ? null : _scanAndPair),
        const SizedBox(height: 10),
        PrimaryButton(label: 'Cancel', outline: true, onTap: () => _go(0)),
      ]));

  Widget _deviceIllustration(Palette p) => Center(
        child: Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
              shape: BoxShape.circle, border: Border.all(color: p.stroke)),
          child: Center(
            child: Container(
              width: 125,
              height: 125,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, border: Border.all(color: p.stroke)),
              child: Center(
                child: Container(
                  width: 59,
                  height: 63,
                  decoration: BoxDecoration(
                      color: p.foreground,
                      borderRadius: BorderRadius.circular(4)),
                  child: const Center(
                      child: Icon(Icons.landscape_outlined,
                          color: Color(0xFFAA6940), size: 31)),
                ),
              ),
            ),
          ),
        ),
      );

  Widget _step(Palette p, bool complete, String title, String subtitle) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 17),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(complete ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 19, color: complete ? p.foreground : p.muted),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Design.body(p, size: 12)),
                    const SizedBox(height: 3),
                    Text(subtitle, style: Design.caption(p, muted: true))
                  ]),
            ),
          ]));

  Widget _addWidget(Palette p) {
    const names = [
      'Calendar',
      'Weather',
      'Clock',
      'To-do',
      'Notes',
      'Photo of the day',
      'Countdown',
      'Home status'
    ];
    const captions = [
      'Daily events',
      'Illustrative demo',
      'Time and date',
      'Tasks for today',
      'Pinned notes',
      'From your photos',
      'Days to an event',
      'Rooms at a glance'
    ];
    final shown = <int>[
      for (var i = 0; i < names.length; i++)
        if (widgetFilter == 0 ||
            (widgetFilter == 1 && [2, 6].contains(i)) ||
            (widgetFilter == 2 && [1, 7].contains(i)) ||
            (widgetFilter == 3 && [0, 3, 4, 5].contains(i)))
          i
    ];
    return _scroll(p, [
      _back(p, 'Hub', 3),
      const SizedBox(height: 22),
      Text('Add widget', style: Design.title(p)),
      const SizedBox(height: 14),
      Row(children: [
        for (var i = 0; i < 4; i++) ...[
          ChoicePill(
              label: ['All', 'Time', 'Home', 'Notes'][i],
              selected: widgetFilter == i,
              compact: true,
              onTap: () => setState(() => widgetFilter = i)),
          const SizedBox(width: 5)
        ]
      ]),
      const SizedBox(height: 18),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 9,
            mainAxisSpacing: 9,
            childAspectRatio: 1.23),
        itemCount: shown.length,
        itemBuilder: (context, i) {
          final n = shown[i];
          final selected = addedWidgets.contains(names[n]);
          return GestureDetector(
            onTap: () {
              setState(() => selected
                  ? addedWidgets.remove(names[n])
                  : addedWidgets.add(names[n]));
              _saveWidgets();
            },
            child: Surface(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    Icon(
                        [
                          Icons.calendar_today_outlined,
                          Icons.cloud_outlined,
                          Icons.schedule,
                          Icons.checklist_outlined,
                          Icons.notes,
                          Icons.photo_outlined,
                          Icons.timer_outlined,
                          Icons.circle_outlined
                        ][n],
                        color: p.foreground,
                        size: 31),
                    const Spacer(),
                    Icon(
                        selected
                            ? Icons.check_circle
                            : Icons.add_circle_outline,
                        size: 19,
                        color: p.foreground)
                  ]),
                  const Spacer(),
                  Text(names[n], style: Design.body(p, size: 12)),
                  const SizedBox(height: 3),
                  Text(captions[n], style: Design.caption(p, muted: true)),
                ])),
          );
        },
      ),
      const SizedBox(height: 12),
      Text(
          'Widgets use local data. Weather shown in Demo Mode is illustrative.',
          style: Design.caption(p, muted: true)),
    ]);
  }
}

class ThumbnailPainter extends CustomPainter {
  ThumbnailPainter(this.seed);
  final int seed;
  @override
  void paint(Canvas canvas, Size size) {
    final colors = [
      const Color(0xFF7D543C),
      const Color(0xFF456774),
      const Color(0xFFC79A3B),
      const Color(0xFF4F6849)
    ];
    canvas.drawRect(
        Offset.zero & size, Paint()..color = colors[seed % colors.length]);
    canvas.drawCircle(Offset(size.width * .55, size.height * .36),
        size.width * .21, Paint()..color = const Color(0xFFE4C192));
    canvas.drawOval(
        Rect.fromLTWH(size.width * .12, size.height * .54, size.width * .77,
            size.height * .7),
        Paint()..color = colors[(seed + 1) % colors.length]);
  }

  @override
  bool shouldRepaint(covariant ThumbnailPainter oldDelegate) =>
      oldDelegate.seed != seed;
}

class ScanQrPage extends StatefulWidget {
  const ScanQrPage({super.key, required this.dark});
  final bool dark;
  @override
  State<ScanQrPage> createState() => _ScanQrPageState();
}

class _ScanQrPageState extends State<ScanQrPage> {
  bool captured = false;
  String? scanError;
  @override
  Widget build(BuildContext context) {
    final p = Palette(widget.dark);
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
          backgroundColor: p.background,
          foregroundColor: p.foreground,
          elevation: 0,
          title: Text('Scan frame QR', style: Design.title(p, size: 18))),
      body: SafeArea(
          child: Column(children: [
        Expanded(
            child: Padding(
                padding: const EdgeInsets.all(22),
                child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: MobileScanner(
                      errorBuilder: (context, error) => Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            'Camera unavailable. Allow camera access for Lumairie in phone settings, then reopen this screen.\n$error',
                            textAlign: TextAlign.center,
                            style: Design.body(p, muted: true),
                          ),
                        ),
                      ),
                      onDetect: (capture) {
                        if (captured || capture.barcodes.isEmpty) return;
                        final raw = capture.barcodes.first.rawValue;
                        if (raw == null) return;
                        try {
                          PairingCredential.parse(raw);
                        } on FormatException {
                          if (scanError == null) {
                            setState(() => scanError =
                                'This is not a Lumairie frame QR code.');
                          }
                          return;
                        }
                        captured = true;
                        Navigator.of(context).pop(raw);
                      },
                    )))),
        if (scanError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Text(scanError!, style: Design.body(p, muted: true)),
          ),
        Padding(
            padding: const EdgeInsets.all(22),
            child: Text(
                'Hold the physical pairing button, then scan the per-frame QR card.',
                style: Design.body(p, muted: true))),
      ])),
    );
  }
}
