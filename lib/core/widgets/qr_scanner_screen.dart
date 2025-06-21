import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:easy_localization/easy_localization.dart';

class QrScannerScreen extends StatefulWidget {
  final String title;

  const QrScannerScreen({
    super.key,
    this.title = 'Scan QR Code',
  });

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController controller = MobileScannerController();
  bool _isHandling = false;

  @override
  void initState() {
    super.initState();
    controller.barcodes.listen((capture) {
      if (_isHandling || capture.barcodes.isEmpty) return;
      final barcode = capture.barcodes.first.rawValue;
      if (barcode != null && barcode.isNotEmpty) {
        _isHandling = true;
        if (mounted) Navigator.pop(context, barcode);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Tarama alanını ekranın ortasında tanımla
    final scanWindow = Rect.fromCenter(
      center: MediaQuery.of(context).size.center(Offset.zero),
      width: MediaQuery.of(context).size.width * 0.8,
      height: MediaQuery.of(context).size.width * 0.8,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: controller,
            scanWindow: scanWindow,
          ),
          // Tarama alanı etrafındaki overlay
          CustomPaint(
            painter: ScannerOverlayPainter(scanWindow: scanWindow),
          ),
          // Kontrol butonları (flaş, kamera değiştirme)
          _buildControls(),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        padding: const EdgeInsets.all(16.0),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black54, Colors.black87],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'qr_scanner.tip'.tr(),
              style: const TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // listen to controller for torchState
                ValueListenableBuilder<MobileScannerState>(
                  valueListenable: controller,
                  builder: (context, state, child) {
                    final icon = state.torchState == TorchState.on
                        ? Icons.flash_on
                        : Icons.flash_off;
                    return _buildControlButton(
                          () => controller.toggleTorch(),
                      icon,
                    );
                  },
                ),
                // listen to controller for cameraDirection
                ValueListenableBuilder<MobileScannerState>(
                  valueListenable: controller,
                  builder: (context, state, child) {
                    final isFront =
                        state.cameraDirection == CameraFacing.front;
                    final icon = isFront
                        ? Icons.camera_front
                        : Icons.camera_rear;
                    return _buildControlButton(
                          () => controller.switchCamera(),
                      icon,
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton(VoidCallback onPressed, IconData icon) {
    return CircleAvatar(
      radius: 30,
      backgroundColor: Colors.black.withOpacity(0.5),
      child: IconButton(
        color: Colors.white,
        icon: Icon(icon, size: 30),
        onPressed: onPressed,
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}

// Tarama alanı etrafındaki görsel efekti çizen sınıf
class ScannerOverlayPainter extends CustomPainter {
  final Rect scanWindow;

  ScannerOverlayPainter({required this.scanWindow});

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPath = Path()..addRect(Offset.zero & size);
    final cutoutPath = Path()
      ..addRRect(
        RRect.fromRectAndRadius(scanWindow, const Radius.circular(12)),
      );
    final overlayPath = Path.combine(
      PathOperation.difference,
      backgroundPath,
      cutoutPath,
    );

    final paint = Paint()..color = Colors.black.withOpacity(0.6);
    canvas.drawPath(overlayPath, paint);

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(scanWindow, const Radius.circular(12)),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}