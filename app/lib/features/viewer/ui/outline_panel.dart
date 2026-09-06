import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Document outline (table of contents / bookmarks) as a collapsible tree.
class OutlinePanel extends StatefulWidget {
  const OutlinePanel({required this.document, required this.onSelect, super.key});

  final PdfDocument document;
  final ValueChanged<PdfDest> onSelect;

  @override
  State<OutlinePanel> createState() => _OutlinePanelState();
}

class _OutlinePanelState extends State<OutlinePanel> {
  late Future<List<PdfOutlineNode>> _outline;

  @override
  void initState() {
    super.initState();
    _outline = widget.document.loadOutline();
  }

  @override
  void didUpdateWidget(OutlinePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.document, widget.document)) {
      _outline = widget.document.loadOutline();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PdfOutlineNode>>(
      future: _outline,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _Message(text: 'Could not read the outline: ${snapshot.error}');
        }
        final nodes = snapshot.data ?? const <PdfOutlineNode>[];
        if (nodes.isEmpty) {
          return const _Message(text: 'This document has no outline.');
        }
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [for (final node in nodes) _OutlineTile(node: node, depth: 0, onSelect: widget.onSelect)],
        );
      },
    );
  }
}

class _OutlineTile extends StatelessWidget {
  const _OutlineTile({required this.node, required this.depth, required this.onSelect});

  final PdfOutlineNode node;
  final int depth;
  final ValueChanged<PdfDest> onSelect;

  @override
  Widget build(BuildContext context) {
    final padding = EdgeInsets.only(left: 16.0 + depth * 12);
    final dest = node.dest;
    final trailing = dest == null ? null : Text('${dest.pageNumber}');

    if (node.children.isEmpty) {
      return ListTile(
        contentPadding: padding.add(const EdgeInsets.only(right: 16)),
        title: Text(node.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: trailing,
        onTap: dest == null ? null : () => onSelect(dest),
      );
    }

    return ExpansionTile(
      tilePadding: padding.add(const EdgeInsets.only(right: 16)),
      title: Text(node.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      // The row expands/collapses on tap, so the page number doubles as the
      // "go here" affordance for a node that is itself a destination.
      trailing: dest == null
          ? null
          : TextButton(onPressed: () => onSelect(dest), child: Text('${dest.pageNumber}')),
      children: [
        for (final child in node.children) _OutlineTile(node: child, depth: depth + 1, onSelect: onSelect),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
