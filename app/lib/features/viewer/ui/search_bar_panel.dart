import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// In-document find bar: query field, match counter and next/prev stepping.
class SearchBarPanel extends StatelessWidget implements PreferredSizeWidget {
  const SearchBarPanel({
    required this.textController,
    required this.searcher,
    required this.onChanged,
    required this.onClose,
    super.key,
  });

  final TextEditingController textController;
  final PdfTextSearcher searcher;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final matchCount = searcher.matches.length;
    final currentIndex = searcher.currentIndex;
    final hasQuery = textController.text.isNotEmpty;
    final label = !hasQuery
        ? ''
        : matchCount == 0
        ? (searcher.isSearching ? 'Searching…' : 'No results')
        : '${(currentIndex ?? 0) + 1} / $matchCount';

    return SafeArea(
      top: false,
      bottom: false,
      child: SizedBox(
        height: preferredSize.height,
        child: Row(
          children: [
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: textController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: onChanged,
                onSubmitted: (_) => searcher.goToNextMatch(),
                decoration: const InputDecoration(
                  hintText: 'Find in document',
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            if (label.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(label, style: theme.textTheme.labelMedium),
              ),
            IconButton(
              tooltip: 'Previous match',
              onPressed: matchCount == 0 ? null : () => searcher.goToPrevMatch(),
              icon: const Icon(Icons.keyboard_arrow_up),
            ),
            IconButton(
              tooltip: 'Next match',
              onPressed: matchCount == 0 ? null : () => searcher.goToNextMatch(),
              icon: const Icon(Icons.keyboard_arrow_down),
            ),
            IconButton(
              tooltip: 'Close search',
              onPressed: onClose,
              icon: const Icon(Icons.close),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}
