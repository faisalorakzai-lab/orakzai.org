import 'package:flutter/material.dart';

import 'app/app_shell.dart';
import 'config/api_config.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  resolveApiBaseUrl();
  runApp(const OrakzaiApp());
}
