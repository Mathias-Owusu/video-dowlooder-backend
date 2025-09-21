import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // Replace with your Heroku URL
  static const String serverBase = "https://your-unique-app-name.herokuapp.com";

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Downloader',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: HomeScreen(serverBase: serverBase),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final String serverBase;
  const HomeScreen({Key? key, required this.serverBase}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTab = 0;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      DownloaderTab(serverBase: widget.serverBase),
      StatusSaverTab(),
      DownloadsTab(),
    ];

    return Scaffold(
      appBar: AppBar(title: Text('Video Manager')),
      body: tabs[_currentTab],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTab,
        onTap: (i) => setState(() => _currentTab = i),
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.download), label: 'Downloader'),
          BottomNavigationBarItem(icon: Icon(Icons.save), label: 'Statuses'),
          BottomNavigationBarItem(icon: Icon(Icons.folder), label: 'Downloads'),
        ],
      ),
    );
  }
}

class DownloaderTab extends StatefulWidget {
  final String serverBase;
  const DownloaderTab({Key? key, required this.serverBase}) : super(key: key);

  @override
  State<DownloaderTab> createState() => _DownloaderTabState();
}

class _DownloaderTabState extends State<DownloaderTab> {
  final TextEditingController _urlController = TextEditingController();
  String _status = '';
  double _progress = 0;
  bool _downloading = false;

  Future<bool> _ensureStoragePermission() async {
    if (Platform.isAndroid) {
      PermissionStatus st = await Permission.storage.request();
      if (st.isGranted) return true;
      // Android 11+: try manage external storage
      if (!st.isGranted) {
        if (await Permission.manageExternalStorage.isDenied) {
          final res = await Permission.manageExternalStorage.request();
          return res.isGranted;
        }
      }
      return false;
    } else {
      // iOS: permission not required for app dir; but to save to Photos you'll need another flow
      return true;
    }
  }

  String _sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  }

  Future<Directory> _getSaveDirectory() async {
    if (Platform.isAndroid) {
      final dir = Directory('/storage/emulated/0/Download');
      if (await dir.exists()) return dir;
    }
    final appDir = await getApplicationDocumentsDirectory();
    return appDir;
  }

  Future<void> _downloadFromServer(String inputUrl) async {
    setState(() {
      _downloading = true;
      _progress = 0;
      _status = "Fetching video info...";
    });

    try {
      final encoded = Uri.encodeComponent(inputUrl);
      final resp = await http.get(Uri.parse("${widget.serverBase}/download?url=$encoded")).timeout(Duration(seconds: 30));
      if (resp.statusCode != 200) {
        setState(() {
          _status = "Server error: ${resp.body}";
          _downloading = false;
        });
        return;
      }

      final data = jsonDecode(resp.body);
      if (data['error'] != null) {
        setState(() {
          _status = "Error: ${data['error']}";
          _downloading = false;
        });
        return;
      }

      final downloadUrl = data['download_url'] as String?;
      final title = (data['title'] as String?) ?? 'video';
      final ext = (data['ext'] as String?) ?? 'mp4';
      final headers = (data['headers'] as Map?)?.cast<String, dynamic>() ?? {};

      if (downloadUrl == null) {
        setState(() {
          _status = "No download URL returned.";
          _downloading = false;
        });
        return;
      }

      final ok = await _ensureStoragePermission();
      if (!ok) {
        setState(() {
          _status = "Storage permission denied.";
          _downloading = false;
        });
        return;
      }

      final saveDir = await _getSaveDirectory();
      final fileName = "${_sanitizeFileName(title)}.${ext.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')}";
      final savePath = p.join(saveDir.path, fileName);

      final dio = Dio();
      // convert headers to Map<String, String>
      final headerMap = <String, String>{};
      headers.forEach((k, v) {
        headerMap[k.toString()] = v.toString();
      });

      setState(() {
        _status = "Downloading to ${savePath.split('/').last}";
      });

      await dio.download(
        downloadUrl,
        savePath,
        options: Options(headers: headerMap, responseType: ResponseType.bytes),
        onReceiveProgress: (received, total) {
          if (total != -1) {
            setState(() {
              _progress = received / total;
              _status = "Downloading: ${(100 * _progress).toStringAsFixed(0)}%";
            });
          }
        },
      );

      setState(() {
        _status = "Saved: $savePath";
        _downloading = false;
        _progress = 0;
      });
    } catch (e) {
      setState(() {
        _status = "Error: $e";
        _downloading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(12),
      child: Column(
        children: [
          TextField(
            controller: _urlController,
            decoration: InputDecoration(
              labelText: "Paste YouTube/Facebook link",
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
          ),
          SizedBox(height: 10),
          ElevatedButton.icon(
            icon: Icon(Icons.download),
            label: Text('Fetch & Download'),
            onPressed: _downloading
                ? null
                : () {
                    final url = _urlController.text.trim();
                    if (url.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Enter a URL')));
                      return;
                    }
                    _downloadFromServer(url);
                  },
          ),
          SizedBox(height: 12),
          if (_downloading) LinearProgressIndicator(value: _progress),
          SizedBox(height: 8),
          Text(_status),
          SizedBox(height: 16),
          Expanded(child: DownloadsList(refreshWhen: _downloading)),
        ],
      ),
    );
  }
}

class StatusSaverTab extends StatefulWidget {
  @override
  State<StatusSaverTab> createState() => _StatusSaverTabState();
}

class _StatusSaverTabState extends State<StatusSaverTab> {
  List<FileSystemEntity> _statuses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStatuses();
  }

  Future<void> _loadStatuses() async {
    setState(() => _loading = true);

    final paths = <String>[
      '/storage/emulated/0/WhatsApp/Media/.Statuses',
      '/storage/emulated/0/WhatsApp Business/Media/.Statuses'
    ];

    List<FileSystemEntity> items = [];
    for (final pth in paths) {
      final dir = Directory(pth);
      if (await dir.exists()) {
        final list = dir.listSync().where((e) {
          final ext = e.path.toLowerCase();
          return ext.endsWith('.jpg') || ext.endsWith('.jpeg') || ext.endsWith('.png') || ext.endsWith('.mp4') || ext.endsWith('.3gp') || ext.endsWith('.webm');
        }).toList();
        items.addAll(list);
      }
    }

    setState(() {
      _statuses = items;
      _loading = false;
    });
  }

  Future<void> _saveToDownloads(FileSystemEntity file) async {
    final ok = await Permission.storage.request();
    if (!ok.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Storage permission required')));
      return;
    }
    final downloads = Directory('/storage/emulated/0/Download');
    if (!await downloads.exists()) {
      await downloads.create(recursive: true);
    }
    final name = p.basename(file.path);
    final target = p.join(downloads.path, name);
    try {
      await File(file.path).copy(target);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to Downloads: $name')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Center(child: CircularProgressIndicator());
    if (_statuses.isEmpty) return Center(child: Text('No WhatsApp statuses found (Android only)'));

    return RefreshIndicator(
      onRefresh: _loadStatuses,
      child: GridView.builder(
        padding: EdgeInsets.all(8),
        itemCount: _statuses.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8),
        itemBuilder: (context, i) {
          final f = _statuses[i];
          final ext = f.path.toLowerCase();
          final isVideo = ext.endsWith('.mp4') || ext.endsWith('.3gp') || ext.endsWith('.webm');
          return GestureDetector(
            onTap: () => _saveToDownloads(f),
            child: Stack(
              children: [
                Positioned.fill(
                  child: isVideo
                      ? Container(
                          color: Colors.black12,
                          child: Center(child: Icon(Icons.videocam, size: 40)),
                        )
                      : Image.file(File(f.path), fit: BoxFit.cover),
                ),
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    padding: EdgeInsets.all(4),
                    color: Colors.black45,
                    child: Text(isVideo ? 'VIDEO' : 'IMG', style: TextStyle(color: Colors.white, fontSize: 10)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class DownloadsTab extends StatefulWidget {
  final bool refreshWhen;
  const DownloadsTab({this.refreshWhen = false});
  @override
  State<DownloadsTab> createState() => _DownloadsTabState();
}

class _DownloadsTabState extends State<DownloadsTab> {
  List<FileSystemEntity> _files = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _scanDownloads();
  }

  Future<void> _scanDownloads() async {
    setState(() => _loading = true);
    List<FileSystemEntity> files = [];
    try {
      final downloads = Directory('/storage/emulated/0/Download');
      if (await downloads.exists()) {
        files = downloads.listSync().where((e) {
          final ext = e.path.toLowerCase();
          return ext.endsWith('.mp4') || ext.endsWith('.mkv') || ext.endsWith('.webm') || ext.endsWith('.jpg') || ext.endsWith('.png');
        }).toList()
          ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      } else {
        final appDoc = await getApplicationDocumentsDirectory();
        if (await appDoc.exists()) {
          files = appDoc.listSync();
        }
      }
    } catch (_) {}
    setState(() {
      _files = files;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Center(child: CircularProgressIndicator());
    if (_files.isEmpty) return Center(child: Text('No downloads found.'));
    return RefreshIndicator(
      onRefresh: _scanDownloads,
      child: ListView.builder(
        itemCount: _files.length,
        itemBuilder: (context, i) {
          final f = _files[i];
          final name = p.basename(f.path);
          final size = (File(f.path).lengthSync() / (1024 * 1024)).toStringAsFixed(2);
          return ListTile(
            leading: Icon(Icons.file_present),
            title: Text(name),
            subtitle: Text('$size MB'),
            trailing: IconButton(
              icon: Icon(Icons.delete),
              onPressed: () async {
                try {
                  await File(f.path).delete();
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Deleted')));
                  _scanDownloads();
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
                }
              },
            ),
          );
        },
      ),
    );
  }
}
