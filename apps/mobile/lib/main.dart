import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Phase 1+ will add: Firebase.initializeApp(), Sentry bootstrap, and
  // eager `AppDatabase` open here (see docs/plan.md section 2, main.dart
  // responsibilities). Kept minimal for the Phase-0 skeleton.
  runApp(const ProviderScope(child: KunimApp()));
}
