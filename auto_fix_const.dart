import 'dart:io';

void main() async {
  print('Running flutter analyze...');
  final result = await Process.run('flutter', ['analyze'], runInShell: true);
  final output = result.stdout.toString() + '\n' + result.stderr.toString();
  
  final regex = RegExp(r'(lib[/\\][^:]+\.dart):(\d+):\d+');
  Map<String, List<int>> errors = {};
  
  for (var line in output.split('\n')) {
    if (line.contains("Extension methods can't be used in constant expressions") || line.contains('const_eval_extension_method')) {
      final match = regex.firstMatch(line);
      if (match != null) {
        final path = match.group(1)!;
        final lineNum = int.parse(match.group(2)!) - 1; // 0-indexed
        errors.putIfAbsent(path, () => []).add(lineNum);
      }
    }
  }
  
  print('Found errors in ${errors.length} files.');
  
  int fixedCount = 0;
  for (var entry in errors.entries) {
    final path = entry.key;
    final errLines = entry.value;
    final f = File(path);
    if (!f.existsSync()) {
      // maybe relative path?
      final absolute = File('${Directory.current.path}/$path');
      if (!absolute.existsSync()) continue;
    }
    
    var fLines = f.readAsLinesSync();
    bool changed = false;
    
    // Sort lines descending so we can safely modify without messing up earlier lines
    errLines.sort((a, b) => b.compareTo(a));
    
    for (var l in errLines) {
      if (l >= fLines.length) continue;
      
      // search backwards up to 30 lines for 'const '
      for (int i = l; i >= 0 && i > l - 30; i--) {
         // Need to be careful to remove 'const ' only if it's actually modifying the widget
         if (fLines[i].contains('const ')) {
            // Replace the last occurrence of 'const ' before the error
            final idx = fLines[i].lastIndexOf('const ');
            if (idx != -1) {
              fLines[i] = fLines[i].replaceRange(idx, idx + 6, ''); // 6 is length of 'const '
              changed = true;
              fixedCount++;
              break;
            }
         }
      }
    }
    
    if (changed) {
      f.writeAsStringSync(fLines.join('\n'));
      print('Fixed some consts in $path');
    }
  }
  print('Removed $fixedCount const keywords.');
}
