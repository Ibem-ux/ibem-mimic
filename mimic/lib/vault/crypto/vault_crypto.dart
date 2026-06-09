// lib/vault/crypto/vault_crypto.dart
// WEB NOTE: web storage is not secure. For testing only. Android uses full encryption.

import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointycastle/export.dart';
import '../../core/services/platform_service.dart';

// ─── Top-level isolate-safe functions ───────────────────────────────────────
// These must be top-level so compute() can serialize them across the isolate boundary.
// All cryptographic parameters (iterations, key length, IV length) are preserved
// exactly — output bytes are byte-identical to the original synchronous code.

Uint8List _deriveKeyIsolate(List<dynamic> args) {
  final pin = args[0] as String;
  final saltBase64 = args[1] as String;
  final iterations = args[2] as int;
  final keyLength = args[3] as int;
  final salt = base64Decode(saltBase64);
  final pinBytes = Uint8List.fromList(utf8.encode(pin));
  final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
  pbkdf2.init(Pbkdf2Parameters(salt, iterations, keyLength));
  return pbkdf2.process(pinBytes);
}

Uint8List _encryptIsolate(List<dynamic> args) {
  final plaintext = args[0] as Uint8List;
  final key = args[1] as Uint8List;
  final iv = args[2] as Uint8List;
  final cipher = CBCBlockCipher(AESEngine());
  final padded = PaddedBlockCipherImpl(PKCS7Padding(), cipher);
  padded.init(
    true,
    PaddedBlockCipherParameters(ParametersWithIV(KeyParameter(key), iv), null),
  );
  final encrypted = padded.process(plaintext);
  final result = Uint8List(iv.length + encrypted.length);
  result.setRange(0, iv.length, iv);
  result.setRange(iv.length, result.length, encrypted);
  return result;
}

Uint8List _decryptIsolate(List<dynamic> args) {
  final ciphertext = args[0] as Uint8List;
  final key = args[1] as Uint8List;
  final ivLength = args[2] as int;
  if (ciphertext.length < ivLength) throw Exception('Invalid ciphertext');
  final iv = ciphertext.sublist(0, ivLength);
  final encrypted = ciphertext.sublist(ivLength);
  final cipher = CBCBlockCipher(AESEngine());
  final padded = PaddedBlockCipherImpl(PKCS7Padding(), cipher);
  padded.init(
    false,
    PaddedBlockCipherParameters(ParametersWithIV(KeyParameter(key), iv), null),
  );
  try {
    return padded.process(encrypted);
  } catch (e) {
    throw Exception('Decryption failed: $e');
  }
}

Uint8List _recoverWithPhraseIsolate(List<dynamic> args) {
  final words = args[0] as List<String>;
  final salt = args[1] as Uint8List;
  final blob = args[2] as Uint8List;
  final mnemonic = words.join(' ');
  final mnemonicBytes = Uint8List.fromList(utf8.encode(mnemonic));
  final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
  pbkdf2.init(Pbkdf2Parameters(salt, 100000, 32));
  final recoveryKey = pbkdf2.process(mnemonicBytes);
  if (blob.length < 16) throw Exception('Invalid blob');
  final iv = blob.sublist(0, 16);
  final encryptedMasterKey = blob.sublist(16);
  final cipher = CBCBlockCipher(AESEngine());
  final padded = PaddedBlockCipherImpl(PKCS7Padding(), cipher);
  padded.init(
    false,
    PaddedBlockCipherParameters(ParametersWithIV(KeyParameter(recoveryKey), iv), null),
  );
  return padded.process(encryptedMasterKey);
}

Uint8List _storeRecoveryBlobIsolate(List<dynamic> args) {
  final masterKey = args[0] as Uint8List;
  final words = args[1] as List<String>;
  final salt = args[2] as Uint8List;
  final mnemonic = words.join(' ');
  final mnemonicBytes = Uint8List.fromList(utf8.encode(mnemonic));
  final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
  pbkdf2.init(Pbkdf2Parameters(salt, 100000, 32));
  final recoveryKey = pbkdf2.process(mnemonicBytes);
  final iv = Uint8List.fromList(List.generate(16, (_) => Random.secure().nextInt(256)));
  final cipher = CBCBlockCipher(AESEngine());
  final padded = PaddedBlockCipherImpl(PKCS7Padding(), cipher);
  padded.init(
    true,
    PaddedBlockCipherParameters(ParametersWithIV(KeyParameter(recoveryKey), iv), null),
  );
  final encrypted = padded.process(masterKey);
  final result = Uint8List(iv.length + encrypted.length);
  result.setRange(0, iv.length, iv);
  result.setRange(iv.length, result.length, encrypted);
  return result;
}

// ─── VaultCrypto class ──────────────────────────────────────────────────────

class VaultCrypto extends ChangeNotifier {
  static VaultCrypto? _instance;
  static VaultCrypto get instance {
    if (_instance == null) {
      throw StateError('VaultCrypto has not been initialized yet.');
    }
    return _instance!;
  }

  final PlatformService _platformService;
  static final Map<String, String> _webKeyStore = {};

  static const int _keyLength = 32;
  static const int _ivLength = 16;
  static const int _pbkdf2Iterations = 100000;
  static const String _storageKeySalt = 'vault_salt';
  static const String _storageKeyPinHash = 'vault_pin_hash';

  Uint8List? _derivedKey;
  bool _isUnlocked = false;
  List<String>? _recoveryWords;

  VaultCrypto(this._platformService) {
    _instance = this;
  }

  bool get isUnlocked => _isUnlocked;

  Uint8List? get derivedKey => _derivedKey;

  Future<void> initialize(String pin) async {
    if (kIsWeb) {
      _webKeyStore[_storageKeySalt] = _generateRandomSalt();
      _webKeyStore[_storageKeyPinHash] = _hashPin(pin);
      _derivedKey = _deriveKeySync(pin, _webKeyStore[_storageKeySalt]!);
      _isUnlocked = true;
      notifyListeners();
      return;
    }

    Uint8List salt;
    final storedSalt = await _platformService.secureRead(_storageKeySalt);
    if (storedSalt != null) {
      salt = base64Decode(storedSalt);
      final storedHash = await _platformService.secureRead(_storageKeyPinHash);
      if (storedHash != null && storedHash == _hashPin(pin)) {
        _derivedKey = await _deriveKey(pin, storedSalt);
        _isUnlocked = true;
        notifyListeners();
        return;
      } else {
        throw Exception('Invalid PIN');
      }
    }

    salt = _generateSecureRandomBytes(16);
    await _platformService.secureWrite(_storageKeySalt, base64Encode(salt));
    await _platformService.secureWrite(_storageKeyPinHash, _hashPin(pin));
    _derivedKey = await _deriveKey(pin, base64Encode(salt));
    _isUnlocked = true;
    notifyListeners();
  }

  Future<Uint8List> encrypt(Uint8List plaintext) async {
    if (!_isUnlocked || _derivedKey == null) throw Exception('Vault is locked');
    if (plaintext.isEmpty) return Uint8List(0);
    if (kIsWeb) {
      return _encryptSync(plaintext, _derivedKey!);
    }
    final iv = _generateSecureRandomBytes(_ivLength);
    return compute(_encryptIsolate, [plaintext, _derivedKey!, iv]);
  }

  Future<Uint8List> decrypt(Uint8List ciphertext) async {
    if (!_isUnlocked || _derivedKey == null) throw Exception('Vault is locked');
    if (ciphertext.isEmpty) return Uint8List(0);
    if (ciphertext.length < _ivLength) throw Exception('Invalid ciphertext');
    if (kIsWeb) {
      return _decryptSync(ciphertext, _derivedKey!);
    }
    return compute(_decryptIsolate, [ciphertext, _derivedKey!, _ivLength]);
  }

  void lock() {
    _isUnlocked = false;
    _derivedKey = null;
    notifyListeners();
  }

  void clearKey() {
    lock();
  }

  Future<void> storeRecoveryBlob([List<String>? recoveryWords]) async {
    if (!_isUnlocked || _derivedKey == null) {
      throw Exception('Vault is locked; cannot store recovery blob');
    }

    final words = recoveryWords ?? _recoveryWords;
    if (words == null || words.length != 12) {
      throw Exception('Invalid or missing recovery phrase');
    }

    final salt = _generateSecureRandomBytes(16);
    final masterKeyBytes = _derivedKey!;
    if (kIsWeb) {
      final blob = _storeRecoveryBlobSync(masterKeyBytes, words, salt);
      await _platformService.secureWrite('recovery_blob', base64Encode(blob));
      await _platformService.secureWrite('recovery_salt', base64Encode(salt));
      return;
    }
    final blob = await compute(_storeRecoveryBlobIsolate, [masterKeyBytes, words, salt]);
    await _platformService.secureWrite('recovery_blob', base64Encode(blob));
    await _platformService.secureWrite('recovery_salt', base64Encode(salt));
  }

  Future<void> changePin(String newPin) async {
    final salt = _generateSecureRandomBytes(16);
    await _platformService.secureWrite(_storageKeySalt, base64Encode(salt));
    await _platformService.secureWrite(_storageKeyPinHash, _hashPin(newPin));
    if (!kIsWeb) {
      await _platformService.secureWrite('vault_pin', newPin);
      await _platformService.secureWrite('wrong_attempts', '0');
    }
    _derivedKey = await _deriveKey(newPin, base64Encode(salt));
    _isUnlocked = true;
    notifyListeners();
  }

  Future<bool> recoverWithPhrase(List<String> recoveryWords) async {
    final storedBlob = await _platformService.secureRead('recovery_blob');
    final storedSalt = await _platformService.secureRead('recovery_salt');
    if (storedBlob == null || storedSalt == null) {
      return false;
    }

    try {
      final salt = base64Decode(storedSalt);
      final blob = base64Decode(storedBlob);
      final masterKey = await compute(_recoverWithPhraseIsolate, [recoveryWords, salt, blob]);

      if (masterKey.length != _keyLength) return false;

      _derivedKey = masterKey;
      _isUnlocked = true;
      _recoveryWords = recoveryWords;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Uint8List> encryptBytes(Uint8List plaintext) async {
    return encryptSystem(plaintext);
  }

  Future<Uint8List> decryptBytes(Uint8List ciphertext) async {
    return decryptSystem(ciphertext);
  }

  Future<void> saveEncryptedFile(String path, Uint8List data) async {
    final encrypted = await encrypt(data);
    if (kIsWeb) {
      _webKeyStore['file_$path'] = base64Encode(encrypted);
      return;
    }
    await _platformService.saveEncryptedFile(path, encrypted);
  }

  Future<Uint8List?> readEncryptedFile(String path) async {
    if (kIsWeb) {
      final encoded = _webKeyStore['file_$path'];
      if (encoded != null) return decrypt(base64Decode(encoded));
      return null;
    }
    final encrypted = await _platformService.readEncryptedFile(path);
    if (encrypted != null) return decrypt(encrypted);
    return null;
  }

  Future<void> deleteEncryptedFile(String path) async {
    if (kIsWeb) {
      _webKeyStore.remove('file_$path');
      return;
    }
    await _platformService.deleteFile(path);
  }

  Future<String> encryptString(String plaintext) async {
    final bytes = Uint8List.fromList(utf8.encode(plaintext));
    final encrypted = await encrypt(bytes);
    return base64Encode(encrypted);
  }

  Future<String> decryptString(String ciphertext) async {
    final bytes = base64Decode(ciphertext);
    final decrypted = await decrypt(bytes);
    return utf8.decode(decrypted);
  }

  Future<Uint8List> _getSystemKey() async {
    final storedKey = await _platformService.secureRead('system_key');
    if (storedKey != null) {
      return base64Decode(storedKey);
    }
    final newKey = _generateSecureRandomBytes(32);
    await _platformService.secureWrite('system_key', base64Encode(newKey));
    return newKey;
  }

  Future<Uint8List> encryptSystem(Uint8List plaintext) async {
    if (plaintext.isEmpty) return Uint8List(0);
    final key = await _getSystemKey();
    final iv = _generateSecureRandomBytes(_ivLength);
    if (kIsWeb) {
      return _encryptSync(plaintext, key);
    }
    return compute(_encryptIsolate, [plaintext, key, iv]);
  }

  Future<Uint8List> decryptSystem(Uint8List ciphertext) async {
    if (ciphertext.isEmpty) return Uint8List(0);
    final key = await _getSystemKey();
    if (ciphertext.length < _ivLength) throw Exception('Invalid ciphertext');
    if (kIsWeb) {
      final iv = ciphertext.sublist(0, _ivLength);
      final encrypted = ciphertext.sublist(_ivLength);
      return _decryptSyncWithIv(encrypted, key, iv);
    }
    return compute(_decryptIsolate, [ciphertext, key, _ivLength]);
  }

  String _hashPin(String pin) {
    final bytes = Uint8List.fromList(utf8.encode(pin));
    final digest = SHA256Digest().process(bytes);
    return base64Encode(digest);
  }

  String _generateRandomSalt() {
    return base64Encode(_generateSecureRandomBytes(16));
  }

  Uint8List _generateSecureRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
  }

  // ─── Synchronous helpers (web path + internal) ─────────────────────────

  Uint8List _deriveKeySync(String pin, String saltBase64) {
    final salt = base64Decode(saltBase64);
    final pinBytes = Uint8List.fromList(utf8.encode(pin));
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
    pbkdf2.init(Pbkdf2Parameters(salt, _pbkdf2Iterations, _keyLength));
    return pbkdf2.process(pinBytes);
  }

  Uint8List _encryptSync(Uint8List plaintext, Uint8List key) {
    final iv = _generateSecureRandomBytes(_ivLength);
    final cipher = _createCipherSync(key, iv, true);
    final encrypted = cipher.process(plaintext);
    final result = Uint8List(iv.length + encrypted.length);
    result.setRange(0, iv.length, iv);
    result.setRange(iv.length, result.length, encrypted);
    return result;
  }

  Uint8List _decryptSync(Uint8List ciphertext, Uint8List key) {
    if (ciphertext.length < _ivLength) throw Exception('Invalid ciphertext');
    final iv = ciphertext.sublist(0, _ivLength);
    final encrypted = ciphertext.sublist(_ivLength);
    return _decryptSyncWithIv(encrypted, key, iv);
  }

  Uint8List _decryptSyncWithIv(Uint8List encrypted, Uint8List key, Uint8List iv) {
    final cipher = _createCipherSync(key, iv, false);
    try {
      return cipher.process(encrypted);
    } catch (e) {
      throw Exception('Decryption failed: $e');
    }
  }

  Uint8List _storeRecoveryBlobSync(Uint8List masterKey, List<String> words, Uint8List salt) {
    final mnemonic = words.join(' ');
    final mnemonicBytes = Uint8List.fromList(utf8.encode(mnemonic));
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
    pbkdf2.init(Pbkdf2Parameters(salt, 100000, 32));
    final recoveryKey = pbkdf2.process(mnemonicBytes);
    final iv = _generateSecureRandomBytes(_ivLength);
    final cipher = _createCipherSync(recoveryKey, iv, true);
    final encrypted = cipher.process(masterKey);
    final result = Uint8List(iv.length + encrypted.length);
    result.setRange(0, iv.length, iv);
    result.setRange(iv.length, result.length, encrypted);
    return result;
  }

  BlockCipher _createCipherSync(Uint8List key, Uint8List iv, bool forEncryption) {
    final cipher = CBCBlockCipher(AESEngine());
    final paddedCipher = PaddedBlockCipherImpl(PKCS7Padding(), cipher);
    paddedCipher.init(
      forEncryption,
      PaddedBlockCipherParameters(ParametersWithIV(KeyParameter(key), iv), null),
    );
    return paddedCipher;
  }

  // ─── Async wrappers used by class methods ──────────────────────────────

  Future<Uint8List> _deriveKey(String pin, String saltBase64) async {
    if (kIsWeb) {
      return _deriveKeySync(pin, saltBase64);
    }
    return compute(_deriveKeyIsolate, [pin, saltBase64, _pbkdf2Iterations, _keyLength]);
  }
}

final vaultCryptoProvider = ChangeNotifierProvider<VaultCrypto>((ref) {
  return VaultCrypto(ref.read(platformServiceProvider));
});
