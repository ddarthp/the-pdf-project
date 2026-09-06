import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pdf_project/app.dart';
import 'package:the_pdf_project/core/view_preferences.dart';
import 'package:the_pdf_project/features/viewer/model/pdf_source.dart';
import 'package:the_pdf_project/features/viewer/model/reading_mode.dart';
import 'package:the_pdf_project/features/viewer/model/view_rotation.dart';
import 'package:the_pdf_project/features/viewer/services/pdf_picker.dart';
import 'package:the_pdf_project/features/library/ui/recent_documents_view.dart';
import 'package:the_pdf_project/features/viewer/ui/viewer_screen.dart';

/// Stands in for the system document picker. Widget tests never reach PDFium,
/// so the fake reports a cancelled pick and records that it was called.
class _FakePdfPicker extends PdfPicker {
  const _FakePdfPicker(this.callCount);

  final List<int> callCount;

  @override
  Future<PdfSource?> pickPdf() async {
    callCount.add(1);
    return null;
  }
}

Widget _wrap(ViewPreferences preferences, PdfPicker picker) => MaterialApp(
  home: ViewerScreen(preferences: preferences, picker: picker),
);

void main() {
  testWidgets('app boots to the empty state with no document open', (tester) async {
    await tester.pumpWidget(const ThePdfProjectApp());

    expect(find.byType(RecentDocumentsView), findsOneWidget);
    expect(find.text('The PDF Project'), findsWidgets);
    expect(find.widgetWithText(FilledButton, 'Open PDF'), findsOneWidget);
  });

  testWidgets('document-only controls stay hidden until a PDF is open', (tester) async {
    await tester.pumpWidget(_wrap(ViewPreferences(), const _FakePdfPicker([])));

    // No page navigation bar, no outline/thumbnail drawer.
    expect(find.byType(BottomAppBar), findsNothing);
    expect(find.byType(Drawer), findsNothing);
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.search)).onPressed, isNull);
  });

  testWidgets('the open button asks the picker for a document', (tester) async {
    final calls = <int>[];
    await tester.pumpWidget(_wrap(ViewPreferences(), _FakePdfPicker(calls)));

    await tester.tap(find.widgetWithText(FilledButton, 'Open PDF'));
    await tester.pumpAndSettle();

    expect(calls, hasLength(1));
    // A cancelled pick leaves the empty state usable rather than stuck.
    expect(find.byType(RecentDocumentsView), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Open PDF')).onPressed, isNotNull);
  });

  for (final mode in ReadingMode.values) {
    testWidgets('the view menu selects ${mode.label}', (tester) async {
      final preferences = ViewPreferences();
      await tester.pumpWidget(_wrap(preferences, const _FakePdfPicker([])));

      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();
      await tester.tap(find.text(mode.label));
      await tester.pumpAndSettle();

      expect(preferences.readingMode, mode);
    });
  }

  testWidgets('the view menu rotates the view a quarter turn at a time', (tester) async {
    final preferences = ViewPreferences();
    await tester.pumpWidget(_wrap(preferences, const _FakePdfPicker([])));

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    expect(find.text('Rotate view (0°)'), findsOneWidget);
    await tester.tap(find.text('Rotate view (0°)'));
    await tester.pumpAndSettle();

    expect(preferences.viewRotation, ViewRotation.clockwise90);

    // The menu label reflects the current angle next time it is opened.
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    expect(find.text('Rotate view (90°)'), findsOneWidget);
  });

  testWidgets('the view menu toggles night mode', (tester) async {
    final preferences = ViewPreferences();
    await tester.pumpWidget(_wrap(preferences, const _FakePdfPicker([])));

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Night mode (invert pages)'));
    await tester.pumpAndSettle();

    expect(preferences.invertPages, isTrue);
  });
}
