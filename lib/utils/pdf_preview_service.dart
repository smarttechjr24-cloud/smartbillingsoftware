import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'template_preview_generator.dart';

/// Service for converting PDF templates to preview images
class PdfPreviewService {
  static const String _previewDirName = 'pdf_previews';
  static const String _dbName = 'smartbilling.db';
  static const int _dbVersion = 2; // Incremented to add theme_previews table

  // Available template keys (A is default, B, C, E are in utils/invoices)
  static const List<String> _availableTemplates = ['A', 'B', 'C', 'E'];

  /// Get database instance
  static Future<Database> _getDatabase() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, _dbName);
    
    return openDatabase(
      dbPath,
      version: _dbVersion,
      onCreate: (db, version) async {
        // Create invoice_theme table
        await db.execute("""
          CREATE TABLE IF NOT EXISTS invoice_theme (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            theme TEXT
          );
        """);
        
        // Create theme_previews table
        await db.execute("""
          CREATE TABLE IF NOT EXISTS theme_previews (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            theme_key TEXT UNIQUE,
            image_path TEXT
          );
        """);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Add theme_previews table if upgrading from version 1
          await db.execute("""
            CREATE TABLE IF NOT EXISTS theme_previews (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              theme_key TEXT UNIQUE,
              image_path TEXT
            );
          """);
        }
      },
    );
  }

  /// Get preview directory path
  static Future<String> _getPreviewDirectory() async {
    final dir = await getApplicationDocumentsDirectory();
    final previewDir = Directory(p.join(dir.path, _previewDirName));
    if (!await previewDir.exists()) {
      await previewDir.create(recursive: true);
    }
    return previewDir.path;
  }

  /// Convert PDF template to image and save locally
  static Future<String?> generatePreviewImage(String themeKey) async {
    try {
      // Check if template is available
      if (!_availableTemplates.contains(themeKey)) {
        debugPrint('⚠️ Template $themeKey not available');
        return null;
      }

      // Use template preview generator to create preview
      final previewPath = await TemplatePreviewGenerator.generatePreview(themeKey);
      if (previewPath == null) {
        debugPrint('⚠️ Failed to generate preview for $themeKey');
        return null;
      }

      // Save path to SQLite
      final db = await _getDatabase();
      await db.insert(
        'theme_previews',
        {
          'theme_key': themeKey,
          'image_path': previewPath,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      debugPrint('✅ Preview generated for theme $themeKey: $previewPath');
      return previewPath;
    } catch (e) {
      debugPrint('❌ Error generating preview for $themeKey: $e');
      return null;
    }
  }

  /// Get preview image path (from cache or generate)
  static Future<String?> getPreviewImagePath(String themeKey) async {
    try {
      // Check SQLite first
      final db = await _getDatabase();
      final result = await db.query(
        'theme_previews',
        where: 'theme_key = ?',
        whereArgs: [themeKey],
        limit: 1,
      );

      if (result.isNotEmpty) {
        final imagePath = result.first['image_path'] as String?;
        if (imagePath != null) {
          final file = File(imagePath);
          if (await file.exists()) {
            return imagePath;
          } else {
            // File doesn't exist, remove from DB and regenerate
            await db.delete(
              'theme_previews',
              where: 'theme_key = ?',
              whereArgs: [themeKey],
            );
          }
        }
      }

      // Not in cache, generate it
      return await generatePreviewImage(themeKey);
    } catch (e) {
      debugPrint('❌ Error getting preview path for $themeKey: $e');
      return null;
    }
  }

  /// Regenerate preview image (force regeneration)
  static Future<String?> regeneratePreview(String themeKey) async {
    try {
      // Delete existing preview from DB
      final db = await _getDatabase();
      await db.delete(
        'theme_previews',
        where: 'theme_key = ?',
        whereArgs: [themeKey],
      );

      // Delete existing file if exists
      final previewDir = await _getPreviewDirectory();
      final fileName = 'preview_$themeKey.png';
      final filePath = p.join(previewDir, fileName);
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }

      // Generate new preview
      return await generatePreviewImage(themeKey);
    } catch (e) {
      debugPrint('❌ Error regenerating preview for $themeKey: $e');
      return null;
    }
  }

  /// Get all available template keys
  static List<String> getAvailableTemplates() {
    return List.from(_availableTemplates);
  }

  /// Check if template exists
  static bool hasTemplate(String themeKey) {
    return _availableTemplates.contains(themeKey);
  }
}

