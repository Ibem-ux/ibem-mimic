import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';

class VaultCrypto {
  static const _storageKeySalt = 'vault_salt';
  static const _pbkdf2Iterations = 100000;
  static const _keyLength = 32; // AES-256 key length in bytes
  static const _ivLength = 16; // AES block size in bytes
  
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  /// Generates cryptographically secure random bytes
  Uint8List _generateSecureRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
  }

  /// Derives a key from PIN using PBKDF2 with a secure salt
  /// Returns the derived key and stores the salt securely
  Future<Uint8List> deriveKey(String pin, {Uint8List? customSalt}) async {
    Uint8List salt;
    if (customSalt != null) {
      salt = customSalt;
    } else {
      final stored = await getStoredSalt();
      if (stored != null) {
        salt = stored;
      } else {
        salt = _generateSecureRandomBytes(16);
        await _storage.write(key: _storageKeySalt, value: base64Encode(salt));
      }
    }
    
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
    derivator.init(Pbkdf2Parameters(salt, _pbkdf2Iterations, _keyLength));
    
    return derivator.process(Uint8List.fromList(utf8.encode(pin)));
  }

  /// Encrypts file data using AES-256-CBC
  Uint8List encryptFile(Uint8List data, Uint8List key) {
    return _encryptData(data, key);
  }

  /// Decrypts file data using AES-256-CBC
  Uint8List decryptFile(Uint8List encryptedData, Uint8List key) {
    return _decryptData(encryptedData, key);
  }

  /// Encrypts string data using AES-256-CBC
  Uint8List encryptString(String text, Uint8List key) {
    final data = Uint8List.fromList(utf8.encode(text));
    return _encryptData(data, key);
  }

  /// Decrypts string data using AES-256-CBC
  String decryptString(Uint8List encryptedData, Uint8List key) {
    final decryptedData = _decryptData(encryptedData, key);
    return utf8.decode(decryptedData);
  }

  /// Retrieves the stored salt from secure storage
  Future<Uint8List?> getStoredSalt() async {
    final saltString = await _storage.read(key: _storageKeySalt);
    if (saltString == null) return null;
    try {
      return base64Decode(saltString);
    } catch (_) {
      // Fallback for legacy character-code stored salts
      return Uint8List.fromList(saltString.codeUnits);
    }
  }

  /// Internal method to encrypt data using AES-256-CBC with PKCS7 padding
  Uint8List _encryptData(Uint8List data, Uint8List key) {
    if (data.isEmpty) {
      return Uint8List(0);
    }
    final iv = _generateSecureRandomBytes(_ivLength);
    
    final cipher = CBCBlockCipher(AESEngine());
    final paddedCipher = PaddedBlockCipherImpl(PKCS7Padding(), cipher);
    
    final params = ParametersWithIV<KeyParameter>(KeyParameter(key), iv);
    paddedCipher.init(
      true, 
      PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(params, null)
    );
    
    final encrypted = paddedCipher.process(data);
    
    // Return IV + encrypted data
    final result = Uint8List(iv.length + encrypted.length);
    result.setRange(0, iv.length, iv);
    result.setRange(iv.length, iv.length + encrypted.length, encrypted);
    
    return result;
  }

  /// Internal method to decrypt data using AES-256-CBC with PKCS7 padding
  Uint8List _decryptData(Uint8List encryptedData, Uint8List key) {
    if (encryptedData.isEmpty) {
      return Uint8List(0);
    }
    if (encryptedData.length < _ivLength) {
      throw Exception('Invalid encrypted data: too short');
    }
    
    final iv = encryptedData.sublist(0, _ivLength);
    final actualEncryptedData = encryptedData.sublist(_ivLength);
    
    final cipher = CBCBlockCipher(AESEngine());
    final paddedCipher = PaddedBlockCipherImpl(PKCS7Padding(), cipher);
    
    final params = ParametersWithIV<KeyParameter>(KeyParameter(key), iv);
    paddedCipher.init(
      false, 
      PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(params, null)
    );
    
    return paddedCipher.process(actualEncryptedData);
  }
}
