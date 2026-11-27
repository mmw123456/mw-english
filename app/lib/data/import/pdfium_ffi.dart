import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// pdfium 原生库不可用。
///
/// 只有两种调用方需要关心：导入页（给人话提示）与测试（缺 DLL 时跳过）。
class PdfiumUnavailable implements Exception {
  const PdfiumUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

/// pdfium 文本抽取（v0.9.0）。
///
/// **为什么直接调 FFI，而不是用 pub 上的 pdfrx / syncfusion：**
/// - pdfrx 那条链（`pdfium_flutter` + `pdfium_dart`）要用 `native_toolchain_c`
///   编一个 C 桥接，开发机没有 MSVC 就编不出来，`flutter test` 里抽不了文本 ——
///   等于 PDF 这条路只能在真机上盲验。
/// - 直接调 `FPDFText_*` 不需要任何编译器：Windows 上加载 `pdfium.dll` 就能跑，
///   所以「抽取 → 分行 → 解析词条」整条链都能进单测。
/// - pdfium 本体是 BSD-3-Clause（预编译包来自 bblanchon/pdfium-binaries），
///   没有 Syncfusion 那类「免费但要同意条款」的许可问题。
///
/// 只用了六个函数，都是 pdfium 稳定多年的 C API：
/// `FPDF_InitLibrary` / `FPDF_LoadMemDocument` / `FPDF_GetPageCount` /
/// `FPDF_LoadPage` / `FPDFText_LoadPage` / `FPDFText_CountChars` /
/// `FPDFText_GetText`（+ 三个 Close）。
class PdfiumText {
  PdfiumText._(this._lib);

  final DynamicLibrary _lib;

  static PdfiumText? _instance;
  static bool _initialized = false;

  /// Windows 上 `flutter test` 用的 DLL。放在 `app/.pdfium/win-x64/`（不进 git，
  /// 由 `_source/fetch_pdfium.py` 下载）。可用 `PDFIUM_DLL` 环境变量覆盖。
  static const String windowsDllRelative = '.pdfium/win-x64/pdfium.dll';

  static PdfiumText get instance {
    final existing = _instance;
    if (existing != null) return existing;
    return _instance = PdfiumText._(_openLibrary());
  }

  /// 库能不能用。测试与 UI 都先问这个，别靠 try/catch 猜。
  static bool get isAvailable {
    try {
      instance;
      return true;
    } catch (_) {
      return false;
    }
  }

  static DynamicLibrary _openLibrary() {
    if (Platform.isAndroid) {
      // 由 android/app/src/main/jniLibs/<abi>/libpdfium.so 提供
      return DynamicLibrary.open('libpdfium.so');
    }
    if (Platform.isWindows) {
      final env = Platform.environment['PDFIUM_DLL'];
      final path = (env != null && env.isNotEmpty) ? env : windowsDllRelative;
      final file = File(path);
      if (!file.existsSync()) {
        throw PdfiumUnavailable(
          '找不到 pdfium.dll（$path）。跑 python _source/fetch_pdfium.py 拉一份。',
        );
      }
      return DynamicLibrary.open(file.absolute.path);
    }
    throw PdfiumUnavailable('当前平台（${Platform.operatingSystem}）没有 pdfium 原生库。');
  }

  // ---- 绑定（懒查找，避免每页都查一遍符号）----
  late final void Function() _init = _lib
      .lookupFunction<Void Function(), void Function()>('FPDF_InitLibrary');

  late final Pointer Function(Pointer<Uint8>, int, Pointer<Uint8>) _loadMem =
      _lib.lookupFunction<Pointer Function(Pointer<Uint8>, Int32, Pointer<Uint8>),
          Pointer Function(Pointer<Uint8>, int, Pointer<Uint8>)>(
    'FPDF_LoadMemDocument',
  );

  late final int Function(Pointer) _pageCount = _lib.lookupFunction<
      Int32 Function(Pointer), int Function(Pointer)>('FPDF_GetPageCount');

  late final Pointer Function(Pointer, int) _loadPage = _lib.lookupFunction<
      Pointer Function(Pointer, Int32),
      Pointer Function(Pointer, int)>('FPDF_LoadPage');

  late final Pointer Function(Pointer) _loadTextPage = _lib.lookupFunction<
      Pointer Function(Pointer), Pointer Function(Pointer)>('FPDFText_LoadPage');

  late final int Function(Pointer) _countChars = _lib.lookupFunction<
      Int32 Function(Pointer), int Function(Pointer)>('FPDFText_CountChars');

  late final int Function(Pointer, int, int, Pointer<Uint16>) _getText = _lib
      .lookupFunction<
          Int32 Function(Pointer, Int32, Int32, Pointer<Uint16>),
          int Function(Pointer, int, int, Pointer<Uint16>)>('FPDFText_GetText');

  late final void Function(Pointer) _closeTextPage = _lib.lookupFunction<
      Void Function(Pointer), void Function(Pointer)>('FPDFText_ClosePage');

  late final void Function(Pointer) _closePage = _lib.lookupFunction<
      Void Function(Pointer), void Function(Pointer)>('FPDF_ClosePage');

  late final void Function(Pointer) _closeDocument = _lib.lookupFunction<
      Void Function(Pointer), void Function(Pointer)>('FPDF_CloseDocument');

  void _ensureInit() {
    if (_initialized) return;
    _init();
    _initialized = true;
  }

  /// 逐页读出纯文本。页与页之间 `await` 一次，让出事件循环 —— 大文件不卡界面，
  /// 也能让调用方在 `onPage` 里刷进度。
  ///
  /// [onPage] 每读完一页回调一次（已读页数 / 总页数）。
  Future<List<String>> readPages(
    Uint8List bytes, {
    void Function(int done, int total)? onPage,
  }) async {
    if (bytes.isEmpty) throw const FormatException('文件是空的');

    _ensureInit();

    final buffer = malloc.allocate<Uint8>(bytes.length);
    Pointer? doc;
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      doc = _loadMem(buffer, bytes.length, nullptr.cast());
      if (doc == nullptr) {
        throw const FormatException('pdfium 打不开这个 PDF（可能已损坏或加密）');
      }

      final total = _pageCount(doc);
      if (total <= 0) throw const FormatException('PDF 里没有页面');

      final pages = <String>[];
      for (var i = 0; i < total; i++) {
        pages.add(_readPage(doc, i));
        onPage?.call(i + 1, total);
        // 每页让一次，避免长循环霸占 UI 线程。
        await Future<void>.delayed(Duration.zero);
      }
      return pages;
    } finally {
      if (doc != null && doc != nullptr) _closeDocument(doc);
      malloc.free(buffer);
    }
  }

  String _readPage(Pointer doc, int index) {
    final page = _loadPage(doc, index);
    if (page == nullptr) return '';
    Pointer? textPage;
    try {
      textPage = _loadTextPage(page);
      if (textPage == nullptr) return '';

      final count = _countChars(textPage);
      if (count <= 0) return '';

      // GetText 要 count+1 个 UTF-16 单元（含结尾 00），返回写入的单元数（含结尾）。
      final buf = malloc.allocate<Uint16>((count + 1) * 2);
      try {
        final written = _getText(textPage, 0, count, buf);
        if (written <= 0) return '';
        final units = buf.asTypedList(written);
        // 去掉结尾的 NUL，再按 UTF-16 码元解码（中文、emoji 都在 BMP 外/内正确）
        final end = units.isNotEmpty && units.last == 0 ? units.length - 1 : units.length;
        return String.fromCharCodes(units.take(end));
      } finally {
        malloc.free(buf);
      }
    } finally {
      if (textPage != null && textPage != nullptr) _closeTextPage(textPage);
      _closePage(page);
    }
  }
}
