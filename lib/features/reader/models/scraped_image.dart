/// مصدر الصورة المستخرجة
/// يحدد من أي طبقة استخراج جاءت الصورة
enum ImageSource {
  /// من فحص DOM مباشرة (الطريقة الأساسية)
  dom,

  /// من اعتراض طلبات الشبكة (onLoadResource)
  network,

  /// من مراقب التغييرات (MutationObserver)
  mutation,
}

/// صورة مستخرجة مع معلومات الترتيب والمصدر
/// تُستخدم داخلياً أثناء عملية الاستخراج والترتيب
class ScrapedImage {
  /// رابط الصورة الكامل
  final String url;

  /// مصدر الاستخراج
  final ImageSource source;

  /// ترتيب العنصر في DOM (index بين أخوته)
  final int domIndex;

  /// الموقع الرأسي الحقيقي (offsetTop المتراكم)
  final double offsetTop;

  /// قيمة CSS flex order (0 افتراضياً)
  final int cssOrder;

  /// رقم الصفحة المستخرج من URL (-1 إذا غير معروف)
  final int pageNumber;

  /// ترتيب التحميل من الشبكة (timestamp order)
  final int networkOrder;

  const ScrapedImage({
    required this.url,
    this.source = ImageSource.dom,
    this.domIndex = 0,
    this.offsetTop = 0,
    this.cssOrder = 0,
    this.pageNumber = -1,
    this.networkOrder = 0,
  });

  ScrapedImage copyWith({
    String? url,
    ImageSource? source,
    int? domIndex,
    double? offsetTop,
    int? cssOrder,
    int? pageNumber,
    int? networkOrder,
  }) {
    return ScrapedImage(
      url: url ?? this.url,
      source: source ?? this.source,
      domIndex: domIndex ?? this.domIndex,
      offsetTop: offsetTop ?? this.offsetTop,
      cssOrder: cssOrder ?? this.cssOrder,
      pageNumber: pageNumber ?? this.pageNumber,
      networkOrder: networkOrder ?? this.networkOrder,
    );
  }

  @override
  String toString() =>
      'ScrapedImage(url: ${url.length > 60 ? '${url.substring(0, 60)}...' : url}, '
      'source: $source, domIndex: $domIndex, pageNum: $pageNumber)';
}
