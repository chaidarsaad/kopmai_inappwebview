import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';

class WebviewPage extends StatefulWidget {
  const WebviewPage({super.key});

  @override
  State<WebviewPage> createState() => _WebviewPageState();
}

class _WebviewPageState extends State<WebviewPage> {
  InAppWebViewController? webViewController;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<bool> _requestPermissions() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      if (sdkInt <= 32) {
        final status = await Permission.storage.request();
        return status.isGranted;
      } else {
        final status = await Permission.photos.request();
        return status.isGranted;
      }
    }
    return true;
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(label: 'OK', onPressed: () {}),
      ),
    );
  }

  Future<void> downloadFile(String url, String fallbackFilename) async {
    final directory = await getApplicationDocumentsDirectory();
    String filename = fallbackFilename;

    Map<String, String> headers = {};
    try {
      final cookieManager = CookieManager.instance();
      final cookies = await cookieManager.getCookies(url: WebUri(url));
      if (cookies.isNotEmpty) {
        headers['Cookie'] = cookies
            .map((c) => "${c.name}=${c.value}")
            .join("; ");
      }
    } catch (e) {
      debugPrint("Gagal ambil cookies: $e");
    }

    // Coba dapatkan nama file dari header
    try {
      final response = await Dio().head(
        url,
        options: Options(headers: headers),
      );
      final contentDisposition = response.headers.value('content-disposition');
      if (contentDisposition != null) {
        final regex = RegExp(r'filename="?([^"]+)"?');
        final match = regex.firstMatch(contentDisposition);
        if (match != null) {
          filename = match.group(1)!;
        }
      }
    } catch (e) {
      debugPrint("Gagal ambil header filename: $e");
    }

    // Buat direktori khusus untuk download
    final downloadDir = Directory('${directory.path}/downloads');
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }

    final savePath = '${downloadDir.path}/$filename';
    debugPrint("Menyimpan ke: $savePath");

    try {
      await Dio().download(
        url,
        savePath,
        options: Options(headers: headers),
        onReceiveProgress: (received, total) {
          if (total != -1) {
            debugPrint("${(received / total * 100).toStringAsFixed(0)}%");
          }
        },
      );

      _showSnackBar("Download berhasil: $filename");

      // Buka file setelah selesai didownload
      await OpenFile.open(savePath);
    } catch (e) {
      debugPrint("Error saat download: $e");
      _showSnackBar("Download gagal: ${e.toString()}");
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        if (webViewController != null) {
          bool canGoBack = await webViewController!.canGoBack();
          if (canGoBack) {
            webViewController!.goBack();
          } else {
            SystemNavigator.pop();
          }
        }
      },
      child: SafeArea(
        child: Scaffold(
          body: InAppWebView(
            initialUrlRequest: URLRequest(
              url: WebUri("https://www.kopmai.com"),
            ),
            // initialUrlRequest: URLRequest(
            //   url: WebUri("http://192.168.100.58:8000"),
            // ),
            initialSettings: InAppWebViewSettings(
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
              javaScriptEnabled: true,
              useShouldOverrideUrlLoading: true,
              useOnDownloadStart: true,
              supportZoom: true,
            ),
            onWebViewCreated: (controller) {
              webViewController = controller;
            },
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              return NavigationActionPolicy.ALLOW;
            },
            onDownloadStartRequest: (controller, downloadStartRequest) async {
              final url = downloadStartRequest.url.toString();
              debugPrint("Mulai download dari: $url");
              await downloadFile(url, "download.xlsx");
            },
          ),
        ),
      ),
    );
  }
}
