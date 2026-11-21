import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Hasil uji internet sungguhan lewat tunnel Xray.
class TunnelProbeResult {
  const TunnelProbeResult(this.ok, this.message);

  final bool ok;
  final String message;
}

/// Menguji apakah tunnel benar-benar bisa membuka HTTPS.
///
/// Probe DNS saja tidak cukup: dengan mode DNS `direct`, query DNS keluar
/// lewat jaringan Android, sehingga tetap sukses walau outbound proxy mati.
/// Di sini kita memakai SOCKS5 Xray (`127.0.0.1:1080`) untuk CONNECT ke
/// `www.google.com:443`, lalu melakukan handshake TLS dan membaca status HTTP.
class TunnelProbe {
  static const int _socksPort = 1080;

  static Future<TunnelProbeResult> check({
    String host = 'www.google.com',
    Duration timeout = const Duration(seconds: 8),
  }) async {
    Socket? socks;
    SecureSocket? secure;
    try {
      socks = await Socket.connect(
        InternetAddress.loopbackIPv4,
        _socksPort,
        timeout: const Duration(seconds: 3),
      );
      final reader = _ByteReader(socks);

      socks.add(const [5, 1, 0]);
      final greeting = await reader.read(2).timeout(timeout);
      if (greeting[0] != 5 || greeting[1] != 0) {
        return const TunnelProbeResult(
          false,
          'SOCKS menolak metode tanpa sandi',
        );
      }

      final name = utf8.encode(host);
      socks.add(<int>[5, 1, 0, 3, name.length, ...name, 0, 443]);
      final head = await reader.read(4).timeout(timeout);
      if (head[0] != 5) {
        return const TunnelProbeResult(false, 'Balasan SOCKS tidak dikenal');
      }
      if (head[1] != 0) {
        return TunnelProbeResult(false, 'CONNECT ditolak (kode ${head[1]})');
      }
      final addressOk = await _skipAddress(reader, head[3]).timeout(timeout);
      if (!addressOk) {
        return const TunnelProbeResult(false, 'Alamat SOCKS tidak dikenal');
      }
      // Iterator sengaja tidak dibatalkan: SecureSocket.secure() akan
      // melepaskan langganan socket ini sendiri. Membatalkannya lebih awal
      // membuat handshake TLS gagal.

      // Sertifikat situs tujuan sengaja tidak divalidasi di sini. Yang diuji
      // adalah jalur tunnel, bukan identitas google.com.
      secure = await SecureSocket.secure(
        socks,
        host: host,
        onBadCertificate: (_) => true,
      ).timeout(timeout);

      secure.write(
        'GET /generate_204 HTTP/1.1\r\n'
        'Host: $host\r\n'
        'User-Agent: BugTunnel-Probe\r\n'
        'Connection: close\r\n'
        '\r\n',
      );
      final status = await _readLine(secure, timeout);
      if (status.contains(' 204') || status.contains(' 200')) {
        return TunnelProbeResult(true, 'HTTPS $host → ${status.trim()}');
      }
      return TunnelProbeResult(
        false,
        status.isEmpty ? 'HTTP kosong' : status.trim(),
      );
    } on TimeoutException {
      return const TunnelProbeResult(false, 'Waktu habis menunggu HTTPS');
    } catch (error) {
      return TunnelProbeResult(false, '$error');
    } finally {
      try {
        secure?.destroy();
      } catch (_) {
        // Socket mungkin sudah ditutup Xray.
      }
      if (secure == null) {
        try {
          socks?.destroy();
        } catch (_) {
          // Abaikan.
        }
      }
    }
  }

  /// Melewati bagian alamat pada balasan CONNECT SOCKS5.
  static Future<bool> _skipAddress(_ByteReader reader, int atyp) async {
    if (atyp == 1) {
      await reader.read(4 + 2);
      return true;
    }
    if (atyp == 4) {
      await reader.read(16 + 2);
      return true;
    }
    if (atyp == 3) {
      final length = (await reader.read(1))[0];
      await reader.read(length + 2);
      return true;
    }
    return false;
  }

  static Future<String> _readLine(SecureSocket socket, Duration timeout) async {
    final iterator = StreamIterator<List<int>>(socket);
    final bytes = <int>[];
    while (true) {
      final moved = await iterator.moveNext().timeout(
        timeout,
        onTimeout: () => false,
      );
      if (!moved) break;
      bytes.addAll(iterator.current);
      for (var i = 0; i < bytes.length; i++) {
        if (bytes[i] == 10) {
          return utf8
              .decode(bytes.sublist(0, i + 1), allowMalformed: true)
              .trim();
        }
      }
    }
    return utf8.decode(bytes, allowMalformed: true).trim();
  }
}

class _ByteReader {
  _ByteReader(Socket socket) : _iterator = StreamIterator<List<int>>(socket);

  final StreamIterator<List<int>> _iterator;
  final List<int> _buffer = [];

  Future<List<int>> read(int count) async {
    while (_buffer.length < count) {
      if (!await _iterator.moveNext()) {
        throw const SocketException('Koneksi SOCKS ditutup');
      }
      _buffer.addAll(_iterator.current);
      if (_buffer.length > 64 * 1024) {
        throw const SocketException('Balasan SOCKS terlalu besar');
      }
    }
    final out = _buffer.sublist(0, count);
    _buffer.removeRange(0, count);
    return out;
  }
}
