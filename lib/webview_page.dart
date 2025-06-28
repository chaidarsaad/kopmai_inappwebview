import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:url_launcher/url_launcher.dart';

class WebviewPage extends StatefulWidget {
  const WebviewPage({super.key});

  @override
  State<WebviewPage> createState() => _WebviewPageState();
}

class _WebviewPageState extends State<WebviewPage> {
  InAppWebViewController? webViewController;
  double _downloadProgress = 0.0;

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

  Future<String> getUniqueFilename(Directory dir, String filename) async {
    String nameWithoutExtension = filename;
    String extension = '';

    final dotIndex = filename.lastIndexOf('.');
    if (dotIndex != -1) {
      nameWithoutExtension = filename.substring(0, dotIndex);
      extension = filename.substring(dotIndex);
    }

    String newName = filename;
    int count = 1;

    while (await File('${dir.path}/$newName').exists()) {
      newName = '$nameWithoutExtension($count)$extension';
      count++;
    }

    return newName;
  }

  Future<void> downloadFile(String url, String fallbackFilename) async {
    try {
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
      } catch (_) {}

      try {
        final response = await Dio().head(
          url,
          options: Options(headers: headers),
        );

        final contentDisposition = response.headers.value(
          'content-disposition',
        );
        final contentType = response.headers.value('content-type');

        if (contentDisposition != null) {
          final regex = RegExp(r'filename="?([^"]+)"?');
          final match = regex.firstMatch(contentDisposition);
          if (match != null) {
            filename = match.group(1)!;
          }
        } else if (!filename.contains('.')) {
          if (contentType != null) {
            final mimeTypeParts = contentType.split('/');
            if (mimeTypeParts.length == 2) {
              String ext = mimeTypeParts[1];
              if (ext.contains(';')) {
                ext = ext.split(';')[0];
              }

              if (ext.isEmpty) {
                ext = 'bin';
              }

              filename = '$filename.$ext';
            }
          } else {
            filename = '$filename.bin';
          }
        }
      } catch (e) {
        if (!filename.contains('.')) {
          filename = '$filename.bin';
        }
      }

      final tempDir = await getTemporaryDirectory();
      filename = await getUniqueFilename(tempDir, filename);
      final tempPath = "${tempDir.path}/$filename";

      await Dio().download(
        url,
        tempPath,
        options: Options(headers: headers),
        onReceiveProgress: (received, total) {
          if (total != -1) {
            setState(() {
              _downloadProgress = received / total;
            });
          }
        },
      );

      _showSnackBar("Download selesai, membuka dialog simpan...");

      final params = SaveFileDialogParams(
        sourceFilePath: tempPath,
        fileName: filename,
      );

      final savedPath = await FlutterFileDialog.saveFile(params: params);

      if (savedPath != null) {
        _showSnackBar("File berhasil disimpan: $savedPath");
      } else {
        _showSnackBar("Simpan dibatalkan oleh pengguna.");
      }
    } catch (e) {
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
          body: Stack(
            children: [
              InAppWebView(
                initialUrlRequest: URLRequest(
                  url: WebUri("https://www.kopmai.com"),
                ),
                initialSettings: InAppWebViewSettings(
                  mediaPlaybackRequiresUserGesture: false,
                  allowsInlineMediaPlayback: true,
                  javaScriptEnabled: true,
                  useShouldOverrideUrlLoading: true,
                  useOnDownloadStart: true,
                  supportZoom: true,
                  forceDark: ForceDark.OFF,
                ),
                onWebViewCreated: (controller) {
                  webViewController = controller;
                },
                shouldOverrideUrlLoading: (controller, navigationAction) async {
                  final uri = navigationAction.request.url;

                  if (uri == null) {
                    return NavigationActionPolicy.ALLOW;
                  }

                  final url = uri.toString();

                  // Tangani wa.me, whatsapp://, tel:, mailto:
                  if (url.startsWith("https://wa.me") ||
                      url.startsWith("whatsapp://") ||
                      url.startsWith("tel:") ||
                      url.startsWith("mailto:")) {
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("Tidak bisa membuka aplikasi terkait."),
                        ),
                      );
                    }
                    return NavigationActionPolicy.CANCEL;
                  }

                  return NavigationActionPolicy.ALLOW;
                },

                onDownloadStartRequest: (
                  controller,
                  downloadStartRequest,
                ) async {
                  final url = downloadStartRequest.url.toString();

                  String fallbackFilename = Uri.parse(url).pathSegments.last;

                  await downloadFile(url, fallbackFilename);
                },
              ),
              if (_downloadProgress > 0 && _downloadProgress < 1)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(value: _downloadProgress),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
