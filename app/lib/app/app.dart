import 'package:material_ui/material_ui.dart';

import 'shell/home_shell.dart';
import 'theme/app_theme.dart';

class MwEnglishApp extends StatelessWidget {
  const MwEnglishApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MW English',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const HomeShell(),
    );
  }
}
