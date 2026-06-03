import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';

void main() {
  group('VaultCrypto', () {
    test('encryptString and decryptString are inverses', () {
      final vaultCrypto = VaultCrypto();
      final key = Uint8List.fromList(List.filled(32, 1)); // 32-byte key for AES-256
      final testText = 'Hello, World!';
      final encrypted = vaultCrypto.encryptString(testText, key);
      final decrypted = vaultCrypto.decryptString(encrypted, key);
      expect(decrypted, equals(testText));
    });

    test('encryptFile and decryptFile are inverses', () {
      final vaultCrypto = VaultCrypto();
      final key = Uint8List.fromList(List.filled(32, 1)); // 32-byte key for AES-256
      final testData = Uint8List.fromList([1, 2, 3, 4, 5]);
      final encrypted = vaultCrypto.encryptFile(testData, key);
      final decrypted = vaultCrypto.decryptFile(encrypted, key);
      expect(decrypted, equals(testData));
    });

    test('Empty string encryption/decryption works', () {
      final vaultCrypto = VaultCrypto();
      final key = Uint8List.fromList(List.filled(32, 1));
      final encrypted = vaultCrypto.encryptString('', key);
      final decrypted = vaultCrypto.decryptString(encrypted, key);
      expect(decrypted, equals(''));
    });

    test('Single character encryption/decryption works', () {
      final vaultCrypto = VaultCrypto();
      final key = Uint8List.fromList(List.filled(32, 1));
      final encrypted = vaultCrypto.encryptString('A', key);
      final decrypted = vaultCrypto.decryptString(encrypted, key);
      expect(decrypted, equals('A'));
    });

    test('Long string encryption/decryption works', () {
      final vaultCrypto = VaultCrypto();
      final key = Uint8List.fromList(List.filled(32, 1));
      final testText = 'A' * 1000; // 1000 character string
      final encrypted = vaultCrypto.encryptString(testText, key);
      final decrypted = vaultCrypto.decryptString(encrypted, key);
      expect(decrypted, equals(testText));
    });
  });
}
