import 'package:flutter/material.dart';

import '../services/pdf_export_service.dart';

/// Asks where a finished PDF should go.
///
/// Returns null if the reader backed out.
Future<PdfExportDestination?> showPdfExportSheet(
  BuildContext context, {
  required String fileName,
  String? note,
}) {
  return showModalBottomSheet<PdfExportDestination>(
    context: context,
    useSafeArea: true,
    builder: (context) => _PdfExportSheet(fileName: fileName, note: note),
  );
}

class _PdfExportSheet extends StatelessWidget {
  const _PdfExportSheet({required this.fileName, this.note});

  final String fileName;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final note = this.note;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fileName, style: theme.textTheme.titleMedium),
                if (note != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    note,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          for (final destination in PdfExportDestination.values)
            ListTile(
              leading: Icon(_iconFor(destination)),
              title: Text(destination.label),
              subtitle: Text(destination.description),
              onTap: () => Navigator.of(context).pop(destination),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  static IconData _iconFor(PdfExportDestination destination) => switch (destination) {
    PdfExportDestination.saveToFiles => Icons.save_alt,
    PdfExportDestination.share => Icons.ios_share,
    PdfExportDestination.print => Icons.print_outlined,
  };
}
