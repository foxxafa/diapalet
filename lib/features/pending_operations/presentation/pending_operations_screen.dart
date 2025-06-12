import 'dart:convert';
import 'package:diapalet/core/sync/pending_operation.dart';
import 'package:diapalet/core/sync/sync_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class PendingOperationsScreen extends StatefulWidget {
  final SyncService syncService;

  const PendingOperationsScreen({
    Key? key,
    required this.syncService,
  }) : super(key: key);

  @override
  _PendingOperationsScreenState createState() => _PendingOperationsScreenState();
}

class _PendingOperationsScreenState extends State<PendingOperationsScreen> {
  late Future<List<PendingOperation>> _pendingOperationsFuture;

  @override
  void initState() {
    super.initState();
    _loadPendingOperations();
  }

  void _loadPendingOperations() {
    setState(() {
      _pendingOperationsFuture = widget.syncService.getPendingOperations();
    });
  }

  Future<void> _showOperationDetails(PendingOperation operation) async {
    final data = jsonDecode(operation.operationData);
    final prettyData = const JsonEncoder.withIndent('  ').convert(data);

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Operation Details (ID: ${operation.id})'),
        content: SingleChildScrollView(
          child: Text(prettyData),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pending Operations'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPendingOperations,
            tooltip: 'Refresh List',
          ),
        ],
      ),
      body: FutureBuilder<List<PendingOperation>>(
        future: _pendingOperationsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No pending operations found.'));
          }

          final operations = snapshot.data!;
          return ListView.builder(
            itemCount: operations.length,
            itemBuilder: (context, index) {
              final operation = operations[index];
              final statusColor = _getStatusColor(operation.status);
              final icon = _getStatusIcon(operation.status);

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  leading: Icon(icon, color: statusColor),
                  title: Text(
                    '${operation.operationType.toUpperCase()} Operation',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Status: ${operation.status}\nCreated: ${DateFormat('yyyy-MM-dd HH:mm').format(operation.createdAt)}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                           await widget.syncService.deleteOperation(operation.id!);
                           _loadPendingOperations();
                        },
                      ),
                      if (operation.status == 'failed')
                        IconButton(
                          icon: const Icon(Icons.sync_problem, color: Colors.orange),
                          onPressed: () async {
                            await widget.syncService.retryOperation(operation.id!);
                            _loadPendingOperations();
                          },
                        ),
                    ],
                  ),
                  onTap: () => _showOperationDetails(operation),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.blue;
      case 'failed':
        return Colors.red;
      case 'synced':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'pending':
        return Icons.cloud_queue;
      case 'failed':
        return Icons.error_outline;
      case 'synced':
        return Icons.cloud_done;
      default:
        return Icons.help_outline;
    }
  }
} 