import 'dart:async';

import 'package:flutter/material.dart';

import '../model/document_quad.dart';
import '../model/scan_filter.dart';
import '../model/scanned_page.dart';
import '../services/page_processor.dart';
import 'corner_adjuster.dart';

/// Checks over one scanned page: where its corners are, and how it is cleaned
/// up.
///
/// Returns the page as adjusted, or null if the reader backed out.
class ScanReviewScreen extends StatefulWidget {
  const ScanReviewScreen({
    required this.page,
    this.processor = const PageProcessor(),
    super.key,
  });

  final ScannedPage page;
  final PageProcessor processor;

  @override
  State<ScanReviewScreen> createState() => _ScanReviewScreenState();
}

class _ScanReviewScreenState extends State<ScanReviewScreen> {
  late ScannedPage _page = widget.page;
  late DocumentQuad _quad = widget.page.quad;
  late ScanFilter _filter = widget.page.filter;
  bool _isProcessing = false;

  /// Whether the corners or the filter have moved away from what the page
  /// currently holds.
  bool get _isStale => _quad != _page.quad || _filter != _page.filter;

  Future<void> _redo() async {
    if (_isProcessing || !_isStale) return;
    setState(() => _isProcessing = true);
    try {
      final redone = await widget.processor.reprocess(_page, quad: _quad, filter: _filter);
      if (!mounted) return;
      setState(() => _page = redone);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not redo that page: $error')));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Check the page'),
        actions: [
          TextButton(
            onPressed: _isProcessing
                ? null
                : () async {
                    // Anything still pending is applied before handing back,
                    // so what was on screen is what comes out.
                    if (_isStale) await _redo();
                    if (context.mounted) Navigator.of(context).pop(_page);
                  },
            child: const Text('Done'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: CornerAdjuster(
                photograph: _page.originalBytes,
                quad: _quad,
                onChanged: (quad) => setState(() => _quad = quad),
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final filter in ScanFilter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(filter.label),
                        selected: _filter == filter,
                        onSelected: (_) => setState(() => _filter = filter),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _isStale ? 'Not applied yet' : 'Up to date',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _isProcessing || !_isStale ? null : () => unawaited(_redo()),
                    icon: _isProcessing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_fix_high),
                    label: Text(_isProcessing ? 'Redoing…' : 'Apply'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
