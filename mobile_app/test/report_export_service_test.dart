import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/report_export_service.dart';

/// Covers ReportExportService.formatDuration/.formatTimestamp/.decodeLog -
/// previously private (`_formatDuration` etc.) and therefore untestable
/// from outside the file, despite being pure data-formatting logic with no
/// Firestore/PDF/file-system dependency. exportChildReport() itself
/// (the Firestore .get() + PDF rendering + share-sheet method) is
/// intentionally NOT covered here - same reasoning
/// usage_tracking_service_test.dart documents for its own
/// native-plugin-touching methods: this codebase doesn't fake Firestore
/// (no fake_cloud_firestore dependency), and there's nothing meaningful to
/// assert about a real share-sheet invocation without a device. What IS
/// covered is the exact logic that turns raw Firestore field values into
/// the strings/lists every PDF section builder renders - the part most
/// likely to silently mis-format real data (a wrong duration bucket, a
/// dropped log entry) without ever throwing.
void main() {
  group('ReportExportService.formatDuration', () {
    test('a non-num value is not available', () {
      expect(ReportExportService.formatDuration(null), 'Not available');
      expect(ReportExportService.formatDuration('120000'), 'Not available');
    });

    test('formats whole hours and remainder minutes', () {
      // 1h 1m, matching the exact case _buildAlertsSection-style doc
      // comments elsewhere in this codebase call out as a real bucket.
      expect(ReportExportService.formatDuration(3660000), '1 h 1 m');
    });

    test('formats hours with zero remainder minutes', () {
      expect(ReportExportService.formatDuration(7200000), '2 h 0 m');
    });

    test('formats minutes only when under an hour', () {
      expect(ReportExportService.formatDuration(90000), '1 m');
    });

    test('formats seconds only when under a minute', () {
      expect(ReportExportService.formatDuration(45000), '45 s');
    });

    test('zero milliseconds formats as 0 s, not blank or "Not available"', () {
      expect(ReportExportService.formatDuration(0), '0 s');
    });

    test('accepts a double, not just an int', () {
      expect(ReportExportService.formatDuration(45000.0), '45 s');
    });
  });

  group('ReportExportService.formatTimestamp', () {
    test('formats a real Firestore Timestamp', () {
      final date = DateTime(2026, 3, 5, 9, 7);
      final result = ReportExportService.formatTimestamp(
        Timestamp.fromDate(date),
      );
      expect(result, '03/05 09:07');
    });

    test('formats an int epoch-milliseconds value', () {
      final date = DateTime(2026, 12, 31, 23, 59);
      final result = ReportExportService.formatTimestamp(
        date.millisecondsSinceEpoch,
      );
      expect(result, '12/31 23:59');
    });

    test('a null value is not available', () {
      expect(ReportExportService.formatTimestamp(null), 'Not available');
    });

    test('an unrecognized type (e.g. a String) is not available', () {
      expect(
        ReportExportService.formatTimestamp('2026-03-05'),
        'Not available',
      );
    });
  });

  group('ReportExportService.decodeLog', () {
    test('a non-list value decodes to an empty list', () {
      expect(ReportExportService.decodeLog(null), isEmpty);
      expect(ReportExportService.decodeLog('not a list'), isEmpty);
      expect(ReportExportService.decodeLog({'a': 1}), isEmpty);
    });

    test('an empty list decodes to an empty list', () {
      expect(ReportExportService.decodeLog(<dynamic>[]), isEmpty);
    });

    test('decodes a list of maps into typed Map<String, dynamic> entries', () {
      final result = ReportExportService.decodeLog([
        {'domain': 'example.com', 'category': 'gambling'},
        {'domain': 'other.com', 'category': 'drugs'},
      ]);

      expect(result, hasLength(2));
      expect(result[0]['domain'], 'example.com');
      expect(result[1]['category'], 'drugs');
    });

    test('drops non-map entries rather than throwing', () {
      final result = ReportExportService.decodeLog([
        {'domain': 'example.com'},
        'a stray string entry',
        42,
        null,
        {'domain': 'kept.com'},
      ]);

      expect(result, hasLength(2));
      expect(result[0]['domain'], 'example.com');
      expect(result[1]['domain'], 'kept.com');
    });

    test('preserves the original order (most-recent-last, as stored)', () {
      final result = ReportExportService.decodeLog([
        {'timestamp': 1},
        {'timestamp': 2},
        {'timestamp': 3},
      ]);

      expect(result.map((e) => e['timestamp']).toList(), [1, 2, 3]);
    });
  });
}
