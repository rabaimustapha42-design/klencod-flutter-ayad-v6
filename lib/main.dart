import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// يلتقط تنزيلات الملفات من نوع blob (Excel / النسخ الاحتياطي)
/// ويرسلها إلى Flutter لمشاركتها أو حفظها.
const String kBlobHook = r'''
(function(){
  if (window.__tdHook) return;
  window.__tdHook = true;
  function send(a){
    var name = a.getAttribute('download') || 'file';
    fetch(a.href).then(function(r){ return r.blob(); }).then(function(b){
      var fr = new FileReader();
      fr.onloadend = function(){
        var d = String(fr.result), i = d.indexOf(',');
        window.flutter_inappwebview.callHandler(
          'saveFile', name, d.slice(i + 1), b.type || 'application/octet-stream');
      };
      fr.readAsDataURL(b);
    });
  }
  var oc = HTMLAnchorElement.prototype.click;
  HTMLAnchorElement.prototype.click = function(){
    if (this.hasAttribute('download') && /^blob:/.test(this.href)) { send(this); return; }
    return oc.apply(this, arguments);
  };
})();
''';

/// زر الرجوع: يغلق القائمة الجانبية، ثم يعود للرئيسية، ثم يخرج.
const String kBackJs = r'''
(function(){
  var s = document.getElementById('side');
  if (s && s.classList.contains('o')) { s.classList.remove('o'); return 1; }
  var h = document.getElementById('v-home');
  if (h && h.hidden && typeof show === 'function') { show('home'); return 1; }
  return 0;
})();
''';

final ValueNotifier<String> _bus = ValueNotifier<String>('v6');
final List<String> _trail = ['v6'];
void dbg(String s) {
  _trail.add(s);
  _bus.value = _trail.join(' > ');
}

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError =
        (d) => dbg('FlutterError: ${d.exceptionAsString()}');
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Color(0xFF0B1E45),
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0B1E45),
      systemNavigationBarIconBrightness: Brightness.light,
    ));
    dbg('main');
    runApp(const TeacherApp());
  }, (e, s) => dbg('Zone: $e'));
}

class TeacherApp extends StatelessWidget {
  const TeacherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'تطبيق الأستاذ',
      home: WebPage(),
    );
  }
}

class WebPage extends StatefulWidget {
  const WebPage({super.key});

  @override
  State<WebPage> createState() => _WebPageState();
}

class _WebPageState extends State<WebPage> {
  InAppWebViewController? _c;
  String? _html;
  String? _err;
  bool _hideDbg = false;

  @override
  void initState() {
    super.initState();
    dbg('flutter ok');
    rootBundle.loadString('assets/index.html').then((s) {
      dbg('html ${s.length}');
      if (mounted) setState(() => _html = s);
    }).catchError((e) {
      dbg('asset error: $e');
      if (mounted) setState(() => _err = 'تعذر قراءة الملف: $e');
    });
  }

  Future<void> _saveFile(String name, String b64, String mime) async {
    try {
      final dir = await getTemporaryDirectory();
      final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final f = File('${dir.path}/$safe');
      await f.writeAsBytes(base64Decode(b64));
      await Share.shareXFiles([XFile(f.path, mimeType: mime)], subject: safe);
    } catch (e) {
      dbg('saveFile error: $e');
    }
  }

  Widget _banner() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: GestureDetector(
        onTap: () => setState(() => _err = null),
        child: Container(
          color: const Color(0xCCB00020),
          padding: const EdgeInsets.all(8),
          child: Text(
            _err ?? '',
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            textDirection: TextDirection.ltr,
          ),
        ),
      ),
    );
  }

  Widget _dbgBar() {
    return ValueListenableBuilder<String>(
      valueListenable: _bus,
      builder: (ctx, v, _) {
        if (_hideDbg) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          color: const Color(0xFF14306B),
          padding: const EdgeInsets.all(6),
          child: Text(
            v,
            style: const TextStyle(color: Colors.white, fontSize: 11),
            textDirection: TextDirection.ltr,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final r = await _c?.evaluateJavascript(source: kBackJs);
        if (r != 1) SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B1E45),
        body: SafeArea(
          child: Column(
            children: [
              _dbgBar(),
              Expanded(
                child: _html == null
                    ? Center(
                        child: _err == null
                            ? const CircularProgressIndicator(
                                color: Colors.white)
                            : Text(_err!,
                                style: const TextStyle(color: Colors.white),
                                textDirection: TextDirection.ltr),
                      )
                    : Stack(
                        children: [
                          Positioned.fill(
                            child: InAppWebView(
                              initialData: InAppWebViewInitialData(
                                data: _html!,
                                mimeType: 'text/html',
                                encoding: 'utf-8',
                                baseUrl: WebUri('https://appassets.local/'),
                              ),
                              initialSettings: InAppWebViewSettings(
                                javaScriptEnabled: true,
                                domStorageEnabled: true,
                                databaseEnabled: true,
                                allowContentAccess: true,
                                mediaPlaybackRequiresUserGesture: false,
                                supportZoom: false,
                                isInspectable: true,
                              ),
                              initialUserScripts:
                                  UnmodifiableListView<UserScript>([
                                UserScript(
                                  source: kBlobHook,
                                  injectionTime: UserScriptInjectionTime
                                      .AT_DOCUMENT_START,
                                ),
                              ]),
                              onWebViewCreated: (controller) {
                                dbg('webview created');
                                _c = controller;
                                controller.addJavaScriptHandler(
                                  handlerName: 'saveFile',
                                  callback: (args) async {
                                    if (args.length >= 3) {
                                      await _saveFile(
                                          args[0].toString(),
                                          args[1].toString(),
                                          args[2].toString());
                                    }
                                    return null;
                                  },
                                );
                              },
                              onLoadStart: (controller, url) {
                                dbg('load start');
                              },
                              onLoadStop: (controller, url) async {
                                final title = await controller.getTitle();
                                dbg('loaded: $title');
                                Future.delayed(const Duration(seconds: 6), () {
                                  if (mounted) {
                                    setState(() => _hideDbg = true);
                                  }
                                });
                              },
                              onReceivedError: (controller, request, error) {
                                dbg('error: ${error.description}');
                                if (mounted) {
                                  setState(() => _err =
                                      'خطأ تحميل: ${error.description} (${request.url})');
                                }
                              },
                              onConsoleMessage: (controller, msg) {
                                if (msg.messageLevel ==
                                    ConsoleMessageLevel.ERROR) {
                                  dbg('JS: ${msg.message}');
                                  if (mounted) {
                                    setState(
                                        () => _err = 'JS: ${msg.message}');
                                  }
                                }
                              },
                            ),
                          ),
                          if (_err != null) _banner(),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}