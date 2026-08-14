import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AdminLogsScreen extends StatelessWidget {
  const AdminLogsScreen({super.key});

  Query<Map<String, dynamic>> get _logsQuery {
    return FirebaseFirestore.instance
        .collection('system_logs')
        .orderBy('timestamp', descending: true)
        .limit(100);
  }

  String _formatTimestamp(dynamic value) {
    if (value is! Timestamp) {
      return 'No timestamp';
    }

    final date = value.toDate().toLocal();

    final year = date.year.toString();
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    final second = date.second.toString().padLeft(2, '0');

    return '$year-$month-$day $hour:$minute:$second';
  }

  String _formatDetails(dynamic details) {
    if (details == null) {
      return '';
    }

    if (details is Map) {
      return details.entries
          .map((entry) => '${entry.key}: ${entry.value}')
          .join('\n');
    }

    return details.toString();
  }

  IconData _levelIcon(String level) {
    switch (level.toLowerCase()) {
      case 'error':
        return Icons.error_outline;
      case 'warning':
        return Icons.warning_amber_outlined;
      default:
        return Icons.info_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('System Logs')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _logsQuery.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Unable to load system logs.\n\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final documents = snapshot.data?.docs ?? [];

          if (documents.isEmpty) {
            return const Center(child: Text('No system logs found.'));
          }

          return RefreshIndicator(
            onRefresh: () async {
              await _logsQuery.get();
            },
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: documents.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final document = documents[index];
                final data = document.data();

                final level = (data['level'] ?? 'info').toString();
                final action = (data['action'] ?? 'Unknown action').toString();
                final message = (data['message'] ?? '').toString();
                final actorUid = data['actor_uid']?.toString();
                final timestamp = _formatTimestamp(data['timestamp']);
                final details = _formatDetails(data['details']);

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(_levelIcon(level)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                action,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                            Text(
                              level.toUpperCase(),
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        if (message.isNotEmpty)
                          Text(
                            message,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),

                        const SizedBox(height: 12),

                        Text(
                          'Time: $timestamp',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),

                        if (actorUid != null && actorUid.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Actor UID: $actorUid',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],

                        if (details.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          const Divider(),
                          const SizedBox(height: 8),
                          Text(
                            'Details',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          SelectableText(details),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
