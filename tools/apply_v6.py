from pathlib import Path
import sys

path = Path(sys.argv[1] if len(sys.argv) > 1 else 'lib/main.dart')
text = path.read_text(encoding='utf-8')


def replace_once(old: str, new: str, label: str):
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'v6 patch failed at {label}: expected 1 match, got {count}')
    text = text.replace(old, new, 1)

if "import 'security.dart';" not in text:
    replace_once(
        "import 'database.dart';",
        "import 'database.dart';\nimport 'security.dart';",
        'security import',
    )

replace_once(
    "home: const HomeScreen(),",
    "home: const AppLockGate(child: HomeScreen()),",
    'app lock gate',
)

report_method = """  Future<void> _openReport() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => const ReportScreen()),
    );
  }
"""
security_method = report_method + """
  Future<void> _openSecuritySettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const SecuritySettingsScreen(),
      ),
    );
  }
"""
replace_once(report_method, security_method, 'security settings method')

create_backup_anchor = "  Future<void> _createBackup() async {"
save_backup_method = """  Future<void> _saveBackup() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final now = DateTime.now();
      final fileName =
          'sklad_backup_${now.year}-${_two(now.month)}-${_two(now.day)}_'
          '${_two(now.hour)}-${_two(now.minute)}.db';
      final backup = await WarehouseDatabase.instance.createBackupFile(
        p.join(tempDir.path, fileName),
      );
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Сохранить резервную копию',
        fileName: fileName,
        bytes: await backup.readAsBytes(),
        type: FileType.custom,
        allowedExtensions: const ['db'],
        mimeType: 'application/octet-stream',
      );
      if (saved == null || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Резервная копия сохранена.')),
      );
      await _reload();
    } catch (error) {
      if (!mounted) return;
      _showError('Не удалось сохранить резервную копию: ${_cleanError(error)}');
    }
  }

""" + create_backup_anchor
replace_once(create_backup_anchor, save_backup_method, 'save backup method')

replace_once(
    "              if (value == 'backup') _createBackup();\n              if (value == 'restore') _restoreBackup();",
    "              if (value == 'security') _openSecuritySettings();\n"
    "              if (value == 'backup_save') _saveBackup();\n"
    "              if (value == 'backup_share') _createBackup();\n"
    "              if (value == 'restore') _restoreBackup();",
    'menu actions',
)

old_backup_item = """              PopupMenuItem(
                value: 'backup',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.backup_outlined),
                  title: Text('Создать резервную копию'),
                ),
              ),
"""
new_backup_items = """              PopupMenuItem(
                value: 'security',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.shield_outlined),
                  title: Text('Защита приложения'),
                ),
              ),
              PopupMenuItem(
                value: 'backup_save',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.save_alt_outlined),
                  title: Text('Сохранить резервную копию'),
                ),
              ),
              PopupMenuItem(
                value: 'backup_share',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.share_outlined),
                  title: Text('Поделиться резервной копией'),
                ),
              ),
"""
replace_once(old_backup_item, new_backup_items, 'backup menu items')

path.write_text(text, encoding='utf-8')
print(f'v6 patch applied to {path}')
