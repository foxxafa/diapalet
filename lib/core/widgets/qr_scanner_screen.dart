// lib/core/widgets/qr_scanner_screen.dart
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});
  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  bool _handling = false;

  @override
  void initState() {
    super.initState();
    controller.barcodes.listen((capture) {
      if (_handling || capture.barcodes.isEmpty) return;
      final v = capture.barcodes.first.rawValue;
      if (v != null && v.isNotEmpty) {
        _handling = true;
        if (mounted) Navigator.pop(context, v);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QR Kodu Tara'),
        actions: [
          /// Flaş düğmesi – state.torchState
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: controller,
            builder: (_, state, __) {
              final torch = state.torchState;
              IconData icon;
              Color color;
              VoidCallback? onPressed = controller.toggleTorch;

              switch (torch) {
                case TorchState.off:
                  icon = Icons.flash_off;
                  color = Colors.grey;
                  break;
                case TorchState.on:
                  icon = Icons.flash_on;
                  color = Colors.yellow;
                  break;
                case TorchState.auto:
                  icon = Icons.flash_auto;
                  color = Colors.blue;
                  break;
                case TorchState.unavailable:
                  icon = Icons.no_flash;
                  color = Colors.red.shade300;
                  onPressed = null;
                  break;
              }
              return IconButton(icon: Icon(icon, color: color), onPressed: onPressed);
            },
          ),

          /// Kamera yönü düğmesi – state.cameraDirection
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: controller,
            builder: (_, state, __) {
              final cam = state.cameraDirection;
              IconData icon;
              switch (cam) {
                case CameraFacing.front:
                  icon = Icons.camera_front;
                  break;
                case CameraFacing.back:
                  icon = Icons.camera_rear;
                  break;
                case CameraFacing.external:
                  icon = Icons.camera;
                  break;
                case CameraFacing.unknown:
                  icon = Icons.help_outline;
                  break;
              }
              return IconButton(icon: Icon(icon), onPressed: controller.switchCamera);
            },
          ),
        ],
      ),

      /// Kamera önizlemesi + yeşil çerçeve
      body: Stack(
        children: [
          MobileScanner(controller: controller),
          Center(
            child: Container(
              width: MediaQuery.of(context).size.width * .7,
              height: MediaQuery.of(context).size.width * .7,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.green, width: 3),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Positioned(
            bottom: 28,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                // LINT FIX: deprecated_member_use (withOpacity -> withAlpha)
                color: Colors.black.withAlpha((255 * 0.5).round()),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'QR kodu çerçevenin içine getirin',
                style: TextStyle(color: Colors.white, fontSize: 15),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
