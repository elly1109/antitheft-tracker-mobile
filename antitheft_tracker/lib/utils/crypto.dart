import 'dart:convert';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'constants.dart';

class Crypto {
  final encrypter = encrypt.Encrypter(encrypt.AES(
    encrypt.Key.fromUtf8(encryptionKey.padRight(32, '\0').substring(0, 32)),
    mode: encrypt.AESMode.cbc,
    padding: 'PKCS7',
  ));

  String encryptData(Map<String, dynamic> data) {
    final iv = encrypt.IV.fromSecureRandom(16);
    final jsonString = jsonEncode(data);
    final encrypted = encrypter.encrypt(jsonString, iv: iv);
    final combined = iv.bytes + encrypted.bytes;
    return base64Encode(combined);
  }

  Map<String, dynamic> decryptData(String encryptedData) {
    final decoded = base64Decode(encryptedData);
    final iv = encrypt.IV(decoded.sublist(0, 16));
    final encrypted = decoded.sublist(16);
    final decrypted = encrypter.decrypt(encrypt.Encrypted(encrypted), iv: iv);
    return jsonDecode(decrypted);
  }
}

final crypto = Crypto();