import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:diapalet/core/sync/sync_service.dart';

class SyncLoadingScreen extends StatefulWidget {
  final Stream<SyncProgress>? progressStream;
  final VoidCallback? onCancel;
  final VoidCallback? onSyncComplete;
  final Function(String error)? onSyncError;

  const SyncLoadingScreen({
    super.key,
    this.progressStream,
    this.onCancel,
    this.onSyncComplete,
    this.onSyncError,
  });

  @override
  State<SyncLoadingScreen> createState() => _SyncLoadingScreenState();
}

class _SyncLoadingScreenState extends State<SyncLoadingScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  SyncProgress? _currentProgress;
  DateTime? _syncStartTime;
  static const int _minimumDisplayTimeMs = 3000; // Minimum 3 saniye göster

  @override
  void initState() {
    super.initState();

    _syncStartTime = DateTime.now(); // Sync başlangıç zamanını kaydet

    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    // Listen to progress updates
    widget.progressStream?.listen((progress) {
      if (mounted) {
        setState(() {
          // Progress güncellemesi sadece ileri doğru olmalı (geri gitmesin)
          if (_currentProgress == null || progress.progress >= (_currentProgress?.progress ?? 0.0)) {
            _currentProgress = progress;
          } else if (progress.stage != _currentProgress?.stage) {
            // Stage değişikliklerinde progress'i kabul et
            _currentProgress = progress;
          }
        });

        // Handle completion and errors with minimum display time
        if (progress.stage == SyncStage.completed) {
          _handleSyncCompletion();
        } else if (progress.stage == SyncStage.error) {
          widget.onSyncError?.call(progress.message ?? 'Unknown error');
        }
      }
    });
  }

  void _handleSyncCompletion() {
    if (_syncStartTime == null) {
      widget.onSyncComplete?.call();
      return;
    }

    final elapsedTime = DateTime.now().difference(_syncStartTime!).inMilliseconds;
    final remainingTime = _minimumDisplayTimeMs - elapsedTime;

    if (remainingTime > 0) {
      // Minimum süre henüz dolmadı, bekle
      debugPrint("⏱️ Sync tamamlandı ama minimum süre için ${remainingTime}ms daha bekleniyor");

      // "Tamamlandı" mesajını göster
      setState(() {
        _currentProgress = const SyncProgress(
          stage: SyncStage.completed,
          tableName: '',
          progress: 1.0,
          message: 'Senkronizasyon tamamlandı ✓',
        );
      });

      // Kalan süre kadar bekle
      Future.delayed(Duration(milliseconds: remainingTime), () {
        if (mounted) {
          widget.onSyncComplete?.call();
        }
      });
    } else {
      // Minimum süre zaten doldu, direkt tamamla
      widget.onSyncComplete?.call();
    }
  }

  String _getTableDisplayName(String tableName) {
    switch (tableName) {
      case 'employees':
        return 'sync.tables.employees'.tr();
      case 'warehouses':
        return 'sync.tables.warehouses'.tr();
      case 'shelfs':
        return 'sync.tables.shelfs'.tr();
      case 'urunler':
        return 'sync.tables.urunler'.tr();
      case 'goods_receipts':
        return 'sync.tables.goods_receipts'.tr();
      case 'goods_receipt_items':
        return 'sync.tables.goods_receipt_items'.tr();
      case 'inventory_stock':
        return 'sync.tables.inventory_stock'.tr();
      case 'wms_putaway_status':
        return 'sync.tables.wms_putaway_status'.tr();
      case 'satin_alma_siparis_fis':
        return 'sync.tables.satin_alma_siparis_fis'.tr();
      case 'satin_alma_siparis_fis_satir':
        return 'sync.tables.satin_alma_siparis_fis_satir'.tr();
      default:
        return tableName; // Fallback to table name if translation not found
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallScreen = screenHeight < 600;

    // Dinamik spacing'ler - küçük ekranlarda daha az boşluk
    final iconSize = isSmallScreen ? 60.0 : 80.0;
    final mainSpacing = isSmallScreen ? 16.0 : 32.0;
    final sectionSpacing = isSmallScreen ? 12.0 : 24.0;
    final padding = isSmallScreen ? 16.0 : 24.0;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                        MediaQuery.of(context).padding.top -
                        MediaQuery.of(context).padding.bottom,
            ),
            child: Padding(
              padding: EdgeInsets.all(padding),
              child: Column(
                children: [
                  SizedBox(height: isSmallScreen ? 20 : 40),

                  // App Logo/Title
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _pulseAnimation.value,
                        child: Icon(
                          Icons.sync,
                          size: iconSize,
                          color: Theme.of(context).primaryColor,
                        ),
                      );
                    },
                  ),

                  SizedBox(height: mainSpacing),

                  // Title
                  Text(
                    'sync.loading_screen.title'.tr(),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  SizedBox(height: sectionSpacing / 2),

                  // Subtitle
                  Text(
                    'sync.loading_screen.subtitle'.tr(),
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  SizedBox(height: mainSpacing + 16),

                  // Progress Bar
                  Container(
                    width: double.infinity,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _currentProgress?.progress,
                        backgroundColor: Colors.transparent,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _currentProgress?.stage == SyncStage.completed
                            ? Colors.green
                            : Theme.of(context).primaryColor,
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: sectionSpacing / 1.5),

                  // Percentage
                  Text(
                    '${((_currentProgress?.progress ?? 0) * 100).toInt()}%',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),

                  SizedBox(height: sectionSpacing),

                  // Current Stage
                  _buildCurrentStage(),

                  SizedBox(height: sectionSpacing / 2),

                  // Records Progress (if available)
                  if (_currentProgress?.processedItems != null &&
                      _currentProgress?.totalItems != null)
                    _buildRecordsProgress(),

                  SizedBox(height: mainSpacing),

                  // Warning Message
                  Container(
                    padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Theme.of(context).colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'sync.loading_screen.do_not_close'.tr(),
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: isSmallScreen ? 20 : 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStage() {
    String stageText = 'sync.loading_screen.progress_preparing'.tr();

    if (_currentProgress?.stage == SyncStage.completed) {
      stageText = _currentProgress?.message ?? 'sync.loading_screen.progress_complete'.tr();
    } else if (_currentProgress?.tableName != null && _currentProgress!.tableName.isNotEmpty) {
      final tableName = _currentProgress!.tableName;
      final tableDisplayName = _getTableDisplayName(tableName);
      stageText = 'sync.loading_screen.progress_downloading'
          .tr()
          .replaceAll('{table}', tableDisplayName);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: _currentProgress?.stage == SyncStage.completed
                ? const Icon(
                    Icons.check_circle,
                    color: Colors.green,
                    size: 20,
                  )
                : CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).primaryColor,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              stageText,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordsProgress() {
    final current = _currentProgress!.processedItems;
    final total = _currentProgress!.totalItems;

    return Text(
      'sync.loading_screen.records_processed'
          .tr()
          .replaceAll('{current}', current.toString())
          .replaceAll('{total}', total.toString()),
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).textTheme.bodySmall?.color,
      ),
    );
  }
}
