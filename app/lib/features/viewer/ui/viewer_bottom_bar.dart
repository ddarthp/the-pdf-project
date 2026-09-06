import 'package:flutter/material.dart';

import '../logic/page_navigation.dart';

/// Page navigation and zoom controls.
class ViewerBottomBar extends StatelessWidget {
  const ViewerBottomBar({
    required this.pageNumber,
    required this.pageCount,
    required this.onFirst,
    required this.onPrevious,
    required this.onNext,
    required this.onLast,
    required this.onJumpToPage,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFitWidth,
    required this.onFitHeight,
    required this.onFitPage,
    super.key,
  });

  final int pageNumber;
  final int pageCount;
  final VoidCallback onFirst;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onLast;
  final VoidCallback onJumpToPage;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFitWidth;
  final VoidCallback onFitHeight;
  final VoidCallback onFitPage;

  @override
  Widget build(BuildContext context) {
    final canGoBack = PageNavigation.canGoBack(pageNumber);
    final canGoForward = PageNavigation.canGoForward(pageNumber, pageCount);

    return BottomAppBar(
      height: 56,
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            IconButton(
              tooltip: 'First page',
              onPressed: canGoBack ? onFirst : null,
              icon: const Icon(Icons.first_page),
            ),
            IconButton(
              tooltip: 'Previous page',
              onPressed: canGoBack ? onPrevious : null,
              icon: const Icon(Icons.chevron_left),
            ),
            TextButton(
              onPressed: pageCount > 0 ? onJumpToPage : null,
              child: Text('$pageNumber / $pageCount'),
            ),
            IconButton(
              tooltip: 'Next page',
              onPressed: canGoForward ? onNext : null,
              icon: const Icon(Icons.chevron_right),
            ),
            IconButton(
              tooltip: 'Last page',
              onPressed: canGoForward ? onLast : null,
              icon: const Icon(Icons.last_page),
            ),
            const VerticalDivider(width: 8, indent: 12, endIndent: 12),
            IconButton(
              tooltip: 'Zoom out',
              onPressed: onZoomOut,
              icon: const Icon(Icons.zoom_out),
            ),
            IconButton(tooltip: 'Zoom in', onPressed: onZoomIn, icon: const Icon(Icons.zoom_in)),
            IconButton(
              tooltip: 'Fit width',
              onPressed: onFitWidth,
              icon: const Icon(Icons.swap_horiz),
            ),
            IconButton(
              tooltip: 'Fit height',
              onPressed: onFitHeight,
              icon: const Icon(Icons.swap_vert),
            ),
            IconButton(
              tooltip: 'Fit page',
              onPressed: onFitPage,
              icon: const Icon(Icons.fit_screen),
            ),
          ],
        ),
      ),
    );
  }
}
