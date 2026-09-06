import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // pdfrx (PDFium) is initialised up front because the viewer opens documents
  // through the engine API before the first pdfrx widget is built.
  await pdfrxFlutterInitialize();
  runApp(const ThePdfProjectApp());
}
