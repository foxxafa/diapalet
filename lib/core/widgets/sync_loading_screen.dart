import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:diapalet/core/sync/sync_service.dart';

class SyncLoadingScreen extends StatefulWidget {
  final Stream<SyncProgress>? progressStream;
  final VoidCallback? onCancel;
  final VoidCallback? onSyncComplete;
  final Function(String error)? onSyncError;

  const SyncLoadingScreen({
    Key? key,
    this.progressStream,
    this.onCancel,
    this.onSyncComplete,
    this.onSyncError,
  }) : super(key: key);

  @override
  State<SyncLoadingScreen> createState() => _SyncLoadingScreenState();
}

class _SyncLoadingScreenState extends State<SyncLoadingScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
  SyncProgress? _currentProgress;

  @override
  void initState() {
    super.initState();
    
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
          _currentProgress = progress;
        });
        
        // Handle completion and errors
        if (progress.stage == SyncStage.completed) {
          widget.onSyncComplete?.call();
        } else if (progress.stage == SyncStage.error) {
          widget.onSyncError?.call(progress.message ?? 'Unknown error');
        }
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const Spacer(flex: 2),
              
              // App Logo/Title
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _pulseAnimation.value,
                    child: Icon(
                      Icons.sync,
                      size: 80,
                      color: Theme.of(context).primaryColor,
                    ),
                  );
                },
              ),
              
              const SizedBox(height: 32),
              
              // Title
              Text(
                'sync.loading_screen.title'.tr(),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 12),
              
              // Subtitle
              Text(
                'sync.loading_screen.subtitle'.tr(),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 48),
              
              // Progress Bar
              Container(
                width: double.infinity,
                height: 8,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _currentProgress?.progress,
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).primaryColor,
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Percentage
              Text(
                '${((_currentProgress?.progress ?? 0) * 100).toInt()}%',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).primaryColor,
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Current Stage
              _buildCurrentStage(),
              
              const SizedBox(height: 16),
              
              // Records Progress (if available)
              if (_currentProgress?.processedItems != null && 
                  _currentProgress?.totalItems != null)
                _buildRecordsProgress(),
              
              const SizedBox(height: 32),
              
              // Warning Message
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
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
              
              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStage() {
    String stageText = 'sync.loading_screen.progress_preparing'.tr();
    
    if (_currentProgress?.tableName != null) {
      final tableName = _currentProgress!.tableName;
      final tableDisplayName = 'sync.tables.$tableName'.tr();
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
            child: CircularProgressIndicator(
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
