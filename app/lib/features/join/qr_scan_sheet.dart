import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../domain/join/join_code.dart';
import '../../domain/join/join_link.dart';
import '../../l10n/app_localizations.dart';

/// Scanning the salon's QR (U2).
///
/// Returns the code, or null if the customer backed out or the camera was
/// refused. **A refusal is a supported path, not an error**: the code screen it
/// came from still takes the code by hand, which is how someone reading it off
/// a counter card gets in anyway.
///
/// Anything that is not a salon code - the wifi QR next to it, a payment QR, a
/// poster URL - is ignored silently and scanning continues. Saying "that is the
/// wrong QR" for every frame would be noise, not help.
class QrScanSheet extends StatefulWidget {
  const QrScanSheet({super.key});

  static Future<JoinCode?> open(BuildContext context) => Navigator.of(context).push<JoinCode>(
        MaterialPageRoute(builder: (_) => const QrScanSheet(), fullscreenDialog: true),
      );

  @override
  State<QrScanSheet> createState() => _QrScanSheetState();
}

class _QrScanSheetState extends State<QrScanSheet> {
  final _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );

  /// Set once a code is found, so a second frame cannot pop the route twice.
  bool _handled = false;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null) continue;
      final code = JoinLink.parse(value);
      if (code != null) {
        _handled = true;
        Navigator.of(context).pop(code);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.joinScanQr)),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _scanner,
            onDetect: _onDetect,
            // A camera the customer refused, or a device without one. Offer the
            // way in that always works rather than a dead viewfinder.
            errorBuilder: (context, error) => Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    l10n.scanCameraUnavailable,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.joinEnterCode),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: Theme.of(context).colorScheme.surface,
              padding: const EdgeInsets.all(16),
              child: SafeArea(
                child: Column(
                  children: [
                    Text(l10n.scanHint, textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l10n.joinEnterCode),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
