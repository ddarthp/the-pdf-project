import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Builds the Copy / Select all menu that appears over a text selection.
///
/// pdfrx has its own version of this menu, but it cannot run inside this app.
/// pdfrx 2.6.1 is written against `package:material_ui`, the Material library
/// that is being split out of the Flutter SDK, while the app is written
/// against `package:flutter/material.dart`. The two declare their own
/// `MaterialLocalizations`, and a `Localizations` lookup matches on the exact
/// type: `MaterialApp` installs the SDK's, pdfrx's toolbar asks for
/// `material_ui`'s, finds nothing and throws while resolving the very first
/// button label. The menu never draws, so selected text can be neither copied
/// nor extended to the whole document.
///
/// Rebuilding the same two buttons with the SDK's own toolbar resolves the
/// labels against the localizations the app really provides. The behaviour is
/// deliberately identical to pdfrx's default menu, including the conditions
/// that hide each button.
Widget? buildTextSelectionContextMenu(
  BuildContext context,
  PdfViewerContextMenuBuilderParams params,
) {
  if (!params.isTextSelectionEnabled) return null;
  final selection = params.textSelectionDelegate;

  final items = <ContextMenuButtonItem>[
    // Copying is only offered once something is selected, and never for a
    // document whose permissions forbid it.
    if (selection.isCopyAllowed && selection.hasSelectedText)
      ContextMenuButtonItem(
        onPressed: selection.copyTextSelection,
        type: ContextMenuButtonType.copy,
      ),
    if (!selection.isSelectingAllText)
      ContextMenuButtonItem(
        onPressed: selection.selectAllText,
        type: ContextMenuButtonType.selectAll,
      ),
  ];
  if (items.isEmpty) return null;

  // The menu is laid out inside the viewer's stack, so it is pinned to the
  // top-left corner and positions itself from the selection anchors.
  return Align(
    alignment: Alignment.topLeft,
    child: AdaptiveTextSelectionToolbar.buttonItems(
      anchors: TextSelectionToolbarAnchors(
        primaryAnchor: params.anchorA,
        secondaryAnchor: params.anchorB,
      ),
      buttonItems: items,
    ),
  );
}
