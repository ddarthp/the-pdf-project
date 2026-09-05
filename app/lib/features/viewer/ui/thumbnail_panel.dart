import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Scrollable page thumbnails; tapping one jumps the viewer to that page.
class ThumbnailPanel extends StatefulWidget {
  const ThumbnailPanel({
    required this.document,
    required this.currentPage,
    required this.onSelect,
    super.key,
  });

  final PdfDocument document;
  final int currentPage;
  final ValueChanged<int> onSelect;

  static const double itemExtent = 188;

  @override
  State<ThumbnailPanel> createState() => _ThumbnailPanelState();
}

class _ThumbnailPanelState extends State<ThumbnailPanel> {
  late final ScrollController _scrollController = ScrollController(
    initialScrollOffset: _offsetFor(widget.currentPage),
  );

  double _offsetFor(int pageNumber) => (pageNumber - 1) * ThumbnailPanel.itemExtent;

  @override
  void didUpdateWidget(ThumbnailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentPage != widget.currentPage && _scrollController.hasClients) {
      final target = _offsetFor(widget.currentPage).clamp(
        _scrollController.position.minScrollExtent,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      controller: _scrollController,
      itemExtent: ThumbnailPanel.itemExtent,
      itemCount: widget.document.pages.length,
      itemBuilder: (context, index) {
        final pageNumber = index + 1;
        final isCurrent = pageNumber == widget.currentPage;
        return InkWell(
          onTap: () => widget.onSelect(pageNumber),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              children: [
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: isCurrent ? scheme.primary : scheme.outlineVariant,
                        width: isCurrent ? 2 : 1,
                      ),
                    ),
                    child: PdfPageView(
                      document: widget.document,
                      pageNumber: pageNumber,
                      // The tile already draws the selection border; the
                      // default drop shadow would fight with it.
                      decoration: const BoxDecoration(color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$pageNumber',
                  style: TextStyle(
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    color: isCurrent ? scheme.primary : null,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
