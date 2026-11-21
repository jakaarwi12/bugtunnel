import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Hasil tes DNS lewat SOCKS5 Xray.
///
/// `ok == null` berarti tes tidak bisa disimpulkan (mis. core belum siap),
/// sehingga koneksi tidak boleh digagalkan hanya karena tes ini.
class DnsProbeResult {
  const DnsProbeResult(this.ok, this.message);

  final bool? ok;
  final String message;
}

/// Mengirim query DNS lewat SOCKS5 UDP milik Xray.
///
/// Ini meniru jalur yang dipakai aplikasi lain: DNS diarahkan ke 8.8.8.8:53
/// dan diproses sesuai aturan routing Xray (langsung atau lewat proxy).
///
/// Perhatian: dengan mode DNS `direct`, balasan berasal dari jaringan Android,
/// bukan dari server. Untuk memastikan tunnel bisa internet, pakai
/// [TunnelProbe.check] dari `tunnel_probe.dart`.
class DnsProbe {
  static const int _socksPort = 1080;

  static Future<DnsProbeResult> check({
    String host = 'www.google.com',
    String server = '8.8.8.8',
    Duration timeout = const Duration(seconds: 6),
  }) async {
    Socket? tcp;
    RawDatagramSocket? udp;
    try {
      tcp = await Socket.connect(
        '127.0.0.1',
        _socksPort,
        timeout: const Duration(seconds: 3),
      );
      final reader = _Reader(tcp);

      tcp.add([5, 1, 0]);
      final greeting = await reader.read(2).timeout(timeout);
      if (greeting[0] != 5 || greeting[1] != 0) {
        return const DnsProbeResult(null, 'SOCKS menolak metode tanpa sandi');
      }

      tcp.add([5, 3, 0, 1, 0, 0, 0, 0, 0, 0]);
      final head = await reader.read(4).timeout(timeout);
      if (head[1] != 0) {
        return DnsProbeResult(false, 'UDP ASSOCIATE ditolak (kode ${head[1]})');
      }

      String relayHost;
      int relayPort;
      final atyp = head[3];
      if (atyp == 1) {
        final b = await reader.read(6).timeout(timeout);
        relayHost = '${b[0]}.${b[1]}.${b[2]}.${b[3]}';
        relayPort = (b[4] << 8) | b[5];
      } else if (atyp == 4) {
        final b = await reader.read(18).timeout(timeout);
        relayHost = InternetAddress.fromRawAddress(
          Uint8List.fromList(b.sublist(0, 16)),
        ).address;
        relayPort = (b[16] << 8) | b[17];
      } else if (atyp == 3) {
        final length = (await reader.read(1).timeout(timeout))[0];
        final b = await reader.read(length + 2).timeout(timeout);
        relayHost = utf8.decode(b.sublist(0, length));
        relayPort = (b[length] << 8) | b[length + 1];
      } else {
        return const DnsProbeResult(false, 'Alamat relay SOCKS tidak dikenal');
      }
      // Sebagian server SOCKS membalas 0.0.0.0:0. Pakai endpoint lokal.
      if (relayHost == '0.0.0.0' || relayHost == '::') {
        relayHost = '127.0.0.1';
      }
      if (relayPort == 0) relayPort = _socksPort;

      udp = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      final query = _buildQuery(host, 0x2f3a);
      final resolver =
          InternetAddress.tryParse(server) ?? InternetAddress('8.8.8.8');
      final ip = resolver.rawAddress;
      if (resolver.type != InternetAddressType.IPv4 || ip.length != 4) {
        return const DnsProbeResult(null, 'Resolver DNS bukan IPv4');
      }
      final packet = <int>[0, 0, 0, 1, ...ip, 0, 53, ...query];
      udp.send(packet, InternetAddress(relayHost), relayPort);

      final completer = Completer<Uint8List?>();
      late StreamSubscription<RawSocketEvent> subscription;
      subscription = udp.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = udp!.receive();
        if (datagram == null) return;
        if (!completer.isCompleted) completer.complete(datagram.data);
      });

      final data = await completer.future.timeout(
        timeout,
        onTimeout: () => null,
      );
      await subscription.cancel();
      if (data == null) {
        return const DnsProbeResult(false, 'Tidak ada balasan DNS');
      }
      return _parse(host, data);
    } on TimeoutException {
      return const DnsProbeResult(false, 'Waktu habis menunggu DNS');
    } catch (error) {
      return DnsProbeResult(null, 'Tes DNS tidak bisa dijalankan: $error');
    } finally {
      try {
        udp?.close();
      } catch (_) {
        // Abaikan.
      }
      try {
        await tcp?.close();
      } catch (_) {
        // Abaikan.
      }
      tcp?.destroy();
    }
  }

  static List<int> _buildQuery(String host, int id) {
    final bytes = <int>[
      id >> 8,
      id & 0xff,
      0x01,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
    ];
    for (final part in host.split('.')) {
      final encoded = utf8.encode(part);
      bytes.add(encoded.length);
      bytes.addAll(encoded);
    }
    bytes.addAll([0x00, 0x00, 0x01, 0x00, 0x01]);
    return bytes;
  }

  static DnsProbeResult _parse(String host, Uint8List data) {
    if (data.length < 5) {
      return const DnsProbeResult(false, 'Balasan DNS terlalu pendek');
    }
    var index = 3;
    final atyp = data[index];
    index++;
    if (atyp == 1) {
      index += 4;
    } else if (atyp == 4) {
      index += 16;
    } else if (atyp == 3) {
      final length = data[index];
      index += 1 + length;
    } else {
      return const DnsProbeResult(false, 'Balasan DNS tidak dikenal');
    }
    index += 2;
    if (index >= data.length) {
      return const DnsProbeResult(false, 'Balasan DNS kosong');
    }

    final dns = data.sublist(index);
    if (dns.length < 12) {
      return const DnsProbeResult(false, 'Balasan DNS tidak lengkap');
    }

    final flags = (dns[2] << 8) | dns[3];
    final rcode = flags & 0x0F;
    if (rcode != 0) {
      return DnsProbeResult(false, 'DNS menolak (kode $rcode)');
    }

    final questions = (dns[4] << 8) | dns[5];
    final answers = (dns[6] << 8) | dns[7];

    var cursor = 12;
    for (var q = 0; q < questions; q++) {
      while (cursor < dns.length && dns[cursor] != 0) {
        cursor += dns[cursor] + 1;
      }
      cursor += 5;
    }

    for (var a = 0; a < answers; a++) {
      if (cursor + 12 > dns.length) break;
      if ((dns[cursor] & 0xC0) == 0xC0) {
        cursor += 2;
      } else {
        while (cursor < dns.length && dns[cursor] != 0) {
          cursor += dns[cursor] + 1;
        }
        cursor++;
      }
      if (cursor + 10 > dns.length) break;
      final type = (dns[cursor] << 8) | dns[cursor + 1];
      final length = (dns[cursor + 8] << 8) | dns[cursor + 9];
      final start = cursor + 10;
      if (type == 1 && length == 4 && start + 4 <= dns.length) {
        final ip =
            '${dns[start]}.${dns[start + 1]}.${dns[start + 2]}.${dns[start + 3]}';
        return DnsProbeResult(true, '$host → $ip');
      }
      cursor = start + length;
    }

    if (answers > 0) {
      return DnsProbeResult(true, '$host dijawab ($answers record)');
    }
    return const DnsProbeResult(false, 'DNS tidak memberi jawaban');
  }
}

class _Reader {
  _Reader(Socket socket) : _iterator = StreamIterator<List<int>>(socket);

  final StreamIterator<List<int>> _iterator;
  final List<int> _buffer = [];

  Future<List<int>> read(int count) async {
    while (_buffer.length < count) {
      if (!await _iterator.moveNext()) {
        throw const SocketException('Koneksi SOCKS ditutup');
      }
      _buffer.addAll(_iterator.current);
    }
    final out = _buffer.sublist(0, count);
    _buffer.removeRange(0, count);
    return out;
  }
}
