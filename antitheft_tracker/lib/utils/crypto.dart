import 'dart:convert';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'constants.dart';

class Crypto {
  final encrypter = encrypt.Encrypter(encrypt.AES(
    encrypt.Key.fromUtf8(encryptionKey.padRight(32, '\0').substring(0, 32)), // Ensure 32-byte key
    mode: encrypt.AESMode.cbc,
    padding: 'PKCS7', // Explicitly use PKCS7 padding
  ));

  String encryptData(String data) {
    final iv = encrypt.IV.fromSecureRandom(16); // 16-byte IV
    final encrypted = encrypter.encrypt(data, iv: iv);
    final combined = iv.bytes + encrypted.bytes; // Prepend IV
    return base64Encode(combined); // Base64 encode IV + ciphertext
  }

  String decryptData(String encryptedData) {
    final decoded = base64Decode(encryptedData);
    final iv = encrypt.IV(decoded.sublist(0, 16));
    final encrypted = decoded.sublist(16);
    return encrypter.decrypt(encrypt.Encrypted(encrypted), iv: iv);
  }
}

final crypto = Crypto();