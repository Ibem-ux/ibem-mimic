// lib/vault/services/notes_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointycastle/export.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../../core/services/platform_service.dart';
import '../crypto/vault_crypto.dart';

// ─── Top-level isolate batch-decrypt function ────────────────────────────────

List<Map<String, dynamic>> _batchDecryptNotesIsolate(Map<String, dynamic> input) {
  final notes = input['notes'] as List<dynamic>;
  final keyBase64 = input['key'] as String;
  final key = base64Decode(keyBase64);
  final results = <Map<String, dynamic>>[];

  for (final note in notes) {
    final encryptedBody = note['encryptedBody'] as String;
    String decrypted = '';
    try {
      final ciphertext = base64Decode(encryptedBody);
      if (ciphertext.isNotEmpty) {
        final iv = ciphertext.sublist(0, 16);
        final encrypted = ciphertext.sublist(16);
        final cipher = CBCBlockCipher(AESEngine());
        final padded = PaddedBlockCipherImpl(PKCS7Padding(), cipher);
        padded.init(
          false,
          PaddedBlockCipherParameters(ParametersWithIV(KeyParameter(key), iv), null),
        );
        final decryptedBytes = padded.process(encrypted);
        decrypted = utf8.decode(decryptedBytes);
      }
    } catch (_) {}

    final result = Map<String, dynamic>.from(note);
    result['encryptedBody'] = decrypted;
    results.add(result);
  }

  return results;
}

class Note {
  final String id;
  final String title;
  final String encryptedBody;
  final DateTime createdAt;
  final DateTime updatedAt;

  Note({
    required this.id,
    required this.title,
    required this.encryptedBody,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'encryptedBody': encryptedBody,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Note.fromJson(Map<String, dynamic> json) => Note(
        id: json['id'] as String,
        title: json['title'] as String,
        encryptedBody: json['encryptedBody'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}

class NotesService {
  final PlatformService _platformService;
  final VaultCrypto _crypto;
  static const String _webKey = 'vault_notes';
  static const String _dbName = 'vault_notes.db';
  Database? _db;

  NotesService(this._platformService, this._crypto);

  Future<void> _ensureDb() async {
    if (kIsWeb) return;
    _db ??= await openDatabase(
      p.join(await getDatabasesPath(), _dbName),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE notes(
            id TEXT PRIMARY KEY,
            title TEXT,
            encryptedBody TEXT,
            created_at TEXT,
            updated_at TEXT
          )
        ''');
      },
    );
  }

  Future<void> addNote(Note note) async {
    final encryptedBody = await _crypto.encryptString(note.encryptedBody);

    if (kIsWeb) {
      final notes = await _getWebNotes();
      notes.add({
        'id': note.id,
        'title': note.title,
        'encryptedBody': encryptedBody,
        'createdAt': note.createdAt.toIso8601String(),
        'updatedAt': note.updatedAt.toIso8601String(),
      });
      await _platformService.secureWrite(_webKey, jsonEncode(notes));
      return;
    }

    await _ensureDb();
    await _db!.insert('notes', {
      'id': note.id,
      'title': note.title,
      'encryptedBody': encryptedBody,
      'created_at': note.createdAt.toIso8601String(),
      'updated_at': note.updatedAt.toIso8601String(),
    });
  }

  Future<void> updateNote(Note note) async {
    final encryptedBody = await _crypto.encryptString(note.encryptedBody);

    if (kIsWeb) {
      final notes = await _getWebNotes();
      final index = notes.indexWhere((n) => n['id'] == note.id);
      if (index != -1) {
        notes[index] = {
          'id': note.id,
          'title': note.title,
          'encryptedBody': encryptedBody,
          'createdAt': note.createdAt.toIso8601String(),
          'updatedAt': note.updatedAt.toIso8601String(),
        };
      }
      await _platformService.secureWrite(_webKey, jsonEncode(notes));
      return;
    }

    await _ensureDb();
    await _db!.update(
      'notes',
      {
        'title': note.title,
        'encryptedBody': encryptedBody,
        'updated_at': note.updatedAt.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [note.id],
    );
  }

  Future<void> deleteNote(String id) async {
    if (kIsWeb) {
      final notes = await _getWebNotes();
      notes.removeWhere((n) => n['id'] == id);
      await _platformService.secureWrite(_webKey, jsonEncode(notes));
      return;
    }

    await _ensureDb();
    await _db!.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Note>> getAllNotes() async {
    if (kIsWeb) {
      final notes = await _getWebNotes();
      final decrypted = await Future.wait(notes.map((n) async {
        String decryptedBody = '';
        try {
          decryptedBody = await _crypto.decryptString(n['encryptedBody'] as String);
        } catch (_) {}
        return Note(
          id: n['id'] as String,
          title: n['title'] as String,
          encryptedBody: decryptedBody,
          createdAt: DateTime.parse(n['createdAt'] as String),
          updatedAt: DateTime.parse(n['updatedAt'] as String),
        );
      }));
      return decrypted;
    }

    await _ensureDb();
    final maps = await _db!.query('notes', orderBy: 'updated_at DESC');

    // Batch-decrypt all notes in a single isolate call to avoid per-note overhead
    final derivedKey = _crypto.derivedKey;
    if (derivedKey != null && derivedKey.isNotEmpty) {
      final input = {
        'notes': maps,
        'key': base64Encode(derivedKey),
      };
      final decryptedMaps = await compute(_batchDecryptNotesIsolate, input);
      return decryptedMaps.map((map) {
        return Note(
          id: map['id'] as String,
          title: map['title'] as String,
          encryptedBody: map['encryptedBody'] as String,
          createdAt: DateTime.parse(map['createdAt'] as String),
          updatedAt: DateTime.parse(map['updatedAt'] as String),
        );
      }).toList();
    }

    // Fallback: no key available, return notes with empty bodies
    return maps.map((map) {
      return Note(
        id: map['id'] as String,
        title: map['title'] as String,
        encryptedBody: '',
        createdAt: DateTime.parse(map['createdAt'] as String),
        updatedAt: DateTime.parse(map['updatedAt'] as String),
      );
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _getWebNotes() async {
    final raw = await _platformService.secureRead(_webKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    return List<Map<String, dynamic>>.from(decoded);
  }
}

final notesServiceProvider = Provider<NotesService>((ref) {
  final platformService = ref.read(platformServiceProvider);
  final crypto = ref.read(vaultCryptoProvider);
  return NotesService(platformService, crypto);
});
