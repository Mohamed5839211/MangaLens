import 'dart:convert';

class SavedChapter {
  final String id;
  final String mangaTitle;
  final String chapterTitle;
  final int imageCount;
  final DateTime savedAt;
  final String folderPath; // Path where images are stored

  SavedChapter({
    required this.id,
    required this.mangaTitle,
    required this.chapterTitle,
    required this.imageCount,
    required this.savedAt,
    required this.folderPath,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'mangaTitle': mangaTitle,
      'chapterTitle': chapterTitle,
      'imageCount': imageCount,
      'savedAt': savedAt.toIso8601String(),
      'folderPath': folderPath,
    };
  }

  factory SavedChapter.fromMap(Map<String, dynamic> map) {
    return SavedChapter(
      id: map['id'],
      mangaTitle: map['mangaTitle'],
      chapterTitle: map['chapterTitle'],
      imageCount: map['imageCount'] ?? 0,
      savedAt: DateTime.parse(map['savedAt']),
      folderPath: map['folderPath'],
    );
  }

  String toJson() => json.encode(toMap());

  factory SavedChapter.fromJson(String source) =>
      SavedChapter.fromMap(json.decode(source));
}
