class ServerNode {
  const ServerNode({
    required this.raw,
    required this.name,
    required this.protocol,
    required this.address,
    required this.port,
    this.latencyMs,
    this.alive = false,
    this.source = '',
  });

  final String raw;
  final String name;
  final String protocol;
  final String address;
  final int port;
  final int? latencyMs;
  final bool alive;
  final String source;

  String get id => raw.split('#').first;
  String get endpoint => '$address:$port';

  ServerNode copyWith({
    String? name,
    int? latencyMs,
    bool? alive,
    bool clearLatency = false,
  }) {
    return ServerNode(
      raw: raw,
      name: name ?? this.name,
      protocol: protocol,
      address: address,
      port: port,
      latencyMs: clearLatency ? null : (latencyMs ?? this.latencyMs),
      alive: alive ?? this.alive,
      source: source,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'raw': raw,
      'name': name,
      'protocol': protocol,
      'address': address,
      'port': port,
      'latencyMs': latencyMs,
      'alive': alive,
      'source': source,
    };
  }

  factory ServerNode.fromJson(Map<String, dynamic> json) {
    return ServerNode(
      raw: json['raw']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Server',
      protocol: json['protocol']?.toString() ?? 'VMess',
      address: json['address']?.toString() ?? '',
      port: int.tryParse(json['port']?.toString() ?? '') ?? 443,
      latencyMs: int.tryParse(json['latencyMs']?.toString() ?? ''),
      alive: json['alive'] == true,
      source: json['source']?.toString() ?? '',
    );
  }
}

class ReleaseInfo {
  const ReleaseInfo({
    required this.tag,
    required this.name,
    required this.notes,
    required this.htmlUrl,
    this.apkUrl,
  });

  final String tag;
  final String name;
  final String notes;
  final String htmlUrl;
  final String? apkUrl;

  String get version => tag.replaceFirst(RegExp(r'^[vV]'), '');
}
