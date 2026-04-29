/// Maps internal tool names to user-friendly labels.
String labelForTool(String toolName) {
  switch (toolName) {
    case 'web_search':
    case 'webSearch':
    case 'searchWeb':
      return 'Searched the web';

    case 'read_url':
    case 'fetchUrl':
    case 'webFetch':
      return 'Read a webpage';

    case 'read_file':
    case 'readFile':
      return 'Read a file';

    case 'bash':
    case 'runCommand':
    case 'shell':
      return 'Ran a command';

    case 'python':
    case 'runPython':
      return 'Ran some code';

    default:
      if (toolName.isEmpty) return 'Used something';
      final pretty = _prettify(toolName);
      return 'Used $pretty';
  }
}

/// Converts snake_case or camelCase to lower-case words separated by spaces.
String _prettify(String name) {
  // Insert spaces before uppercase letters (camelCase → camel Case)
  final spaced = name.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (m) => '${m[1]} ${m[2]}',
  );
  // Replace underscores with spaces
  return spaced.replaceAll('_', ' ').toLowerCase();
}
