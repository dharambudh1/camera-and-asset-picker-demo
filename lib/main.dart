import 'dart:io';

import 'package:camera_and_asset_picker/singleton/navigation_singleton.dart';
import 'package:camera_and_asset_picker/singleton/picker_utils.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:transparent_image/transparent_image.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
      ),
      home: const MyHomePage(),
      debugShowCheckedModeBanner: false,
      navigatorKey: Singleton().navigatorStateKey,
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key}) : super(key: key);

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final ValueNotifier<List<File>> filePaths = ValueNotifier<List<File>>([]);
  final maxLength = 6;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<File>>(
      valueListenable: filePaths,
      builder: (BuildContext context, List<File> value, Widget? child) {
        return Scaffold(
          appBar: AppBar(title: const Text("Camera & Asset Picker Demo")),
          floatingActionButton: FloatingActionButton(
            onPressed: () async {
              if (filePaths.value.length < maxLength) {
                await onPressed((value) {
                  _showMyDialog(value);
                });
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      "You've reached the maximum assets upload limit",
                    ),
                  ),
                );
              }
            },
            child: const Icon(Icons.add),
          ),
          body: SafeArea(
            child: GridView.builder(
              itemCount: filePaths.value.length,
              padding: const EdgeInsets.all(12.0),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 12.0,
                mainAxisSpacing: 12.0,
                childAspectRatio: 3.0 / 3.0,
              ),
              itemBuilder: (BuildContext context, int index) {
                return Container(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.all(
                      Radius.circular(5),
                    ),
                    border: Border.all(
                      color: Colors.white,
                      width: 1,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: ClipRRect(
                          borderRadius: const BorderRadius.all(
                            Radius.circular(5),
                          ),
                          child: mediaSelector(index),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: () {
                            filePaths.value = List.from(filePaths.value)
                              ..removeAt(index);
                          },
                          child: Container(
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.red,
                            ),
                            padding: const EdgeInsets.all(2.0),
                            child: const Icon(Icons.delete),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget mediaSelector(int index) {
    String mimeType = lookupMimeType(filePaths.value[index].path) ?? "";
    if (mimeType.startsWith("image/")) {
      return Image.file(filePaths.value[index]);
    } else if (mimeType.startsWith("video/")) {
      return FutureBuilder<File>(
        future: PickerUtils().generateThumbnailForVideo(
          path: filePaths.value[index].path,
        ),
        builder: (BuildContext context, AsyncSnapshot<File> snapshot) {
          return snapshot.data == null
              ? Image.memory(kTransparentImage)
              : Image.file(snapshot.data ?? File(""));
        },
      );
    } else {
      return const SizedBox();
    }
  }

  Future onPressed(Function(List<File>) showMyDialogCallBack) async {
    return showBarModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (BuildContext context) {
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: PickerType.values.length,
          itemBuilder: (BuildContext context, int index) {
            return ListTile(
              title: Text(PickerType.values[index].name),
              leading: Icon(
                index == 0 ? Icons.camera_outlined : Icons.photo_outlined,
              ),
              onTap: () async {
                Navigator.of(context).pop();
                List<File> discardedFiles = [];
                filePaths.value += await PickerUtils().checkPermissionAndPick(
                  // maxFileSize must be in byte
                  maxFileSize: 5000000,
                  shouldFollowMaxSizeInCamera: false,
                  shouldFollowMaxSizeInAssets: false,
                  type: PickerType.values[index],
                  filePaths: filePaths,
                  maxLength: maxLength,
                  discardedFiles: (List<File> value) {
                    discardedFiles = value;
                  },
                  permDeniedList: (Map<Permission, PermissionStatus> map) {},
                );
                if (discardedFiles.isNotEmpty) {
                  showMyDialogCallBack(discardedFiles);
                }
              },
            );
          },
        );
      },
    );
  }

  Future<void> _showMyDialog(List<File> discardedFiles) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Discarded files',
              ),
              const SizedBox(
                height: 12,
              ),
              Text(
                'Important note: The files which are greater than 5 MB will be discard automatically.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              itemCount: discardedFiles.length,
              itemBuilder: (BuildContext context, int index) {
                return ListTile(
                  title: Text(
                    discardedFiles[index].path,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                );
              },
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: Navigator.of(context).pop,
              child: const Text('Okay'),
            ),
          ],
        );
      },
    );
  }
}
