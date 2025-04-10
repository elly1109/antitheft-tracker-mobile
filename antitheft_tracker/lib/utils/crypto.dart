import 'dart:convert'; // Import for base64 encoding/decoding
import 'package:encrypt/encrypt.dart' as encrypt;
import 'constants.dart';

class Crypto {
  final encrypter = encrypt.Encrypter(encrypt.AES(
    encrypt.Key.fromUtf8(encryptionKey.substring(0, 32)), // Ensure 32 bytes
    mode: encrypt.AESMode.cbc,
  ));

  String encryptData(String data) {
    final iv = encrypt.IV.fromLength(16);
    final encrypted = encrypter.encrypt(data, iv: iv);
    return base64.encode(iv.bytes + encrypted.bytes); // Use base64 from dart:convert
  }

  String decryptData(String encryptedData) {
    final decoded = base64.decode(encryptedData); // Use base64 from dart:convert
    final iv = encrypt.IV(decoded.sublist(0, 16));
    final encrypted = decoded.sublist(16);
    return encrypter.decrypt(encrypt.Encrypted(encrypted), iv: iv);
  }
}

final crypto = Crypto();