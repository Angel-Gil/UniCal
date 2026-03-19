import 'dart:io';

void main() {
  final regex = RegExp(r'(lib[/\\][^:]+\.dart):(\d+):\d+');
  final file = File('analyze.txt');
  if (!file.existsSync()) {
    print('No analyze.txt');
    return;
  }
  
  final lines = file.readAsLinesSync();
  Map<String, List<int>> errors = {};
  
  for (var line in lines) {
    if (line.contains("Extension methods can't be used in constant expressions") || line.contains('const_eval_extension_method')) {
      final match = regex.firstMatch(line);
      if (match != null) {
        final path = match.group(1)!;
        final lineNum = int.parse(match.group(2)!) - 1; // 0-indexed
        errors.putIfAbsent(path, () => []).add(lineNum);
      }
    }
  }
  
  int fixedCount = 0;
  for (var entry in errors.entries) {
    final path = entry.key;
    final errLines = entry.value;
    final f = File(path);
    if (!f.existsSync()) continue;
    
    var fLines = f.readAsLinesSync();
    bool changed = false;
    
    for (var l in errLines) {
      if (l >= fLines.length) continue;
      
      // search backwards up to 30 lines for 'const '
      for (int i = l; i >= 0 && i > l - 30; i--) {
         if (fLines[i].contains('const ')) {
            fLines[i] = fLines[i].replaceFirst('const ', '');
            changed = true;
            fixedCount++;
            break;
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
