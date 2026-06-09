// lib/vault/crypto/recovery_phrase.dart
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';
import 'bip39_wordlist.dart';

class RecoveryPhrase {
  static List<String> generate() {
    final random = Random.secure();
    return List.generate(12, (_) {
      final index = random.nextInt(kBip39Wordlist.length);
      return kBip39Wordlist[index];
    });
  }

  static Future<Uint8List> deriveKey(List<String> words, Uint8List salt) async {
    if (kIsWeb) {
      return _deriveKeySync(words, salt);
    }
    return compute(_deriveKeyIsolate, [words, salt]);
  }

  static bool isValidWord(String word) {
    return kBip39Wordlist.contains(word.trim().toLowerCase());
  }
}

// ─── Top-level isolate function ─────────────────────────────────────────────

Uint8List _deriveKeyIsolate(List<dynamic> args) {
  final words = args[0] as List<String>;
  final salt = args[1] as Uint8List;
  final mnemonic = words.join(' ');
  final mnemonicBytes = Uint8List.fromList(utf8.encode(mnemonic));
  final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
  pbkdf2.init(Pbkdf2Parameters(salt, 100000, 32));
  return pbkdf2.process(mnemonicBytes);
}

// ─── Sync fallback (web path) ───────────────────────────────────────────────

Uint8List _deriveKeySync(List<String> words, Uint8List salt) {
  final mnemonic = words.join(' ');
  final mnemonicBytes = Uint8List.fromList(utf8.encode(mnemonic));
  final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
  pbkdf2.init(Pbkdf2Parameters(salt, 100000, 32));
  return pbkdf2.process(mnemonicBytes);
}
