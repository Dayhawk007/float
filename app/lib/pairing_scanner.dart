import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'float_theme.dart';

class PairingScanner extends StatefulWidget {
  const PairingScanner({super.key});

  @override
  State<PairingScanner> createState() => _PairingScannerState();
}

class _PairingScannerState extends State<PairingScanner> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handled = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final value = capture.barcodes.isEmpty
        ? null
        : capture.barcodes.first.rawValue;
    if (value == null || !value.startsWith('float://pair?')) {
      setState(() => _error = 'That is not a Float pairing QR code.');
      return;
    }
    _handled = true;
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: FloatTheme.ink,
    appBar: AppBar(
      backgroundColor: FloatTheme.ink,
      foregroundColor: Colors.white,
      elevation: 0,
      title: const Text('Scan pairing QR'),
    ),
    body: Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(controller: _controller, onDetect: _onDetect),
        Center(
          child: Container(
            width: 236,
            height: 236,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 2),
              borderRadius: BorderRadius.circular(22),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            color: FloatTheme.ink,
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 34),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Point your camera at the QR code in the Float CLI.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFD0D0D0)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
