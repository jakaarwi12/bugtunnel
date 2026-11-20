enum LogLevel { info, success, warning, error }

class LogEntry {
  LogEntry({required this.time, required this.level, required this.message});

  final DateTime time;
  final LogLevel level;
  final String message;

  String get clock {
    String two(int value) => value.toString().padLeft(2, '0');
    String three(int value) => value.toString().padLeft(3, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}.${three(time.millisecond)}';
  }

  String get label => switch (level) {
    LogLevel.info => 'INFO',
    LogLevel.success => 'OK',
    LogLevel.warning => 'WARN',
    LogLevel.error => 'ERROR',
  };

  String toLine() => '[$clock] ${label.padRight(5)} $message';
}
