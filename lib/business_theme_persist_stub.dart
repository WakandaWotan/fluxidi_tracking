final Map<String, String> _memory = <String, String>{};

Future<String?> readBusinessThemeFileContents(String fileName) async {
  return _memory[fileName];
}

Future<void> writeBusinessThemeFileContents(
  String fileName,
  String contents,
) async {
  _memory[fileName] = contents;
}

void resetBusinessThemeFilePersistForTest() {
  _memory.clear();
}
