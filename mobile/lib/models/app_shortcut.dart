class AppShortcut {
  final String id;
  final String label;
  final String command;
  final String? iconImagePath;

  const AppShortcut({
    required this.id,
    required this.label,
    required this.command,
    this.iconImagePath,
  });

  AppShortcut copyWith({
    String? id,
    String? label,
    String? command,
    String? iconImagePath,
    bool clearIcon = false,
  }) {
    return AppShortcut(
      id: id ?? this.id,
      label: label ?? this.label,
      command: command ?? this.command,
      iconImagePath: clearIcon ? null : (iconImagePath ?? this.iconImagePath),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'command': command,
      'iconImagePath': iconImagePath,
    };
  }

  factory AppShortcut.fromJson(Map<String, dynamic> json) {
    return AppShortcut(
      id: (json['id'] as String?) ?? '',
      label: (json['label'] as String?) ?? '',
      command: (json['command'] as String?) ?? '',
      iconImagePath: json['iconImagePath'] as String?,
    );
  }
}
