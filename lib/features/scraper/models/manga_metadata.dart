class MangaMetadata {
  final String title;
  final String coverUrl;
  final String url;
  final String? status;
  final String? rating;
  final String? description;
  final String? author;
  final List<String>? genres;
  final List<ChapterMetadata> chapters;

  MangaMetadata({
    required this.title,
    required this.coverUrl,
    required this.url,
    this.status,
    this.rating,
    this.description,
    this.author,
    this.genres,
    this.chapters = const [],
  });

  MangaMetadata copyWith({
    String? title,
    String? coverUrl,
    String? url,
    String? status,
    String? rating,
    String? description,
    String? author,
    List<String>? genres,
    List<ChapterMetadata>? chapters,
  }) {
    return MangaMetadata(
      title: title ?? this.title,
      coverUrl: coverUrl ?? this.coverUrl,
      url: url ?? this.url,
      status: status ?? this.status,
      rating: rating ?? this.rating,
      description: description ?? this.description,
      author: author ?? this.author,
      genres: genres ?? this.genres,
      chapters: chapters ?? this.chapters,
    );
  }
}

class ChapterMetadata {
  final String title;
  final String url;
  final DateTime? date;

  ChapterMetadata({
    required this.title,
    required this.url,
    this.date,
  });
}
