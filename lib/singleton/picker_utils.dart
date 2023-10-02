import 'dart:developer';
import 'dart:io';

import 'package:camera_and_asset_picker/singleton/navigation_singleton.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as thumbnail;
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:wechat_camera_picker/wechat_camera_picker.dart';

enum PickerType { camera, asset }

class PickerUtils {
  static final PickerUtils _singleton = PickerUtils._internal();

  factory PickerUtils() {
    return _singleton;
  }

  PickerUtils._internal();

  BuildContext ctx = Singleton().navigatorStateKey.currentState!.context;

  Future<Map<Permission, PermissionStatus>> checkPermission({
    required PickerType type,
  }) async {
    Map<Permission, PermissionStatus> temp = {};
    PermissionStatus status = PermissionStatus.denied;
    bool cameraIsGranted = await Permission.camera.isGranted;
    bool storageIsGranted = await Permission.storage.isGranted;
    bool photosIsGranted = await Permission.photos.isGranted;
    bool photosIsLimited = await Permission.photos.isLimited;
    switch (type) {
      case PickerType.camera:
        if (!cameraIsGranted) {
          status = await Permission.camera.request();
          temp.addAll({Permission.camera: status});
        }
        if (!storageIsGranted) {
          status = await Permission.storage.request();
          temp.addAll({Permission.storage: status});
        }
        if (Platform.isIOS) {
          if (!photosIsGranted || !photosIsLimited) {
            status = await Permission.photos.request();
            temp.addAll({Permission.photos: status});
          }
        }
        break;
      case PickerType.asset:
        if (!storageIsGranted) {
          status = await Permission.storage.request();
          temp.addAll({Permission.storage: status});
        }
        if (Platform.isIOS) {
          if (!photosIsGranted || !photosIsLimited) {
            status = await Permission.photos.request();
            temp.addAll({Permission.photos: status});
          }
        }
        break;
    }
    return Future.value(temp);
  }

  Future<List<File>> checkPermissionAndPick({
    required int maxFileSize,
    required bool shouldFollowMaxSizeInCamera,
    required bool shouldFollowMaxSizeInAssets,
    required PickerType type,
    required ValueNotifier<List<File>> filePaths,
    required int maxLength,
    required Function(List<File>) discardedFiles,
    required Function(Map<Permission, PermissionStatus>) permDeniedList,
  }) async {
    List<File> tempList = [];
    ScaffoldMessengerState messengerState = ScaffoldMessenger.of(ctx);
    Map<Permission, PermissionStatus> status =
        await checkPermission(type: type);
    bool isGranted = status.containsValue(PermissionStatus.granted);
    bool isLimited = status.containsValue(PermissionStatus.limited);
    // bool hasAccess = isGranted || isLimited;
    bool hasAccess = isGranted || isLimited || status.isEmpty;
    if (hasAccess) {
      if (filePaths.value.length < maxLength) {
        switch (type) {
          case PickerType.camera:
            tempList = await pickFromCamera(
              discardedFiles: discardedFiles,
              maxFileSize: maxFileSize,
              shouldFollowMaxSizeInCamera: shouldFollowMaxSizeInCamera,
            );
            break;
          case PickerType.asset:
            tempList = await pickFromAssets(
              filePaths: filePaths,
              maxLength: maxLength,
              discardedFiles: discardedFiles,
              maxFileSize: maxFileSize,
              shouldFollowMaxSizeInAssets: shouldFollowMaxSizeInAssets,
            );
            break;
        }
      } else {
        messengerState.showSnackBar(
          const SnackBar(
            content: Text(
              "You've reached the maximum assets upload limit",
            ),
          ),
        );
      }
    } else {
      permDeniedList(status);
      messengerState.showSnackBar(
        SnackBar(
          content: Text(
            status.toString(),
          ),
          duration: const Duration(seconds: 10),
        ),
      );
    }
    return Future.value(tempList);
  }

  Future<List<File>> pickFromCamera({
    required Function(List<File>) discardedFiles,
    required int maxFileSize,
    required bool shouldFollowMaxSizeInCamera,
  }) async {
    AssetEntity imageFile = await fetchImagesFromCamera();
    List<List<AssetEntity>> separationList = separationFunction(imageFile);
    List<AssetEntity> imagesList = separationList[0];
    List<AssetEntity> videosList = separationList[1];
    List<CroppedFile> croppedPaths = await assetImgToCroppedFiles(
      assetFiles: imagesList,
    );
    List<File> tempFilePaths = await croppedFilesToFiles(
      croppedPaths: croppedPaths,
    );
    List<File> temp = await assetVideosToFiles(assetFiles: videosList);
    tempFilePaths.addAll(temp);
    List<File> finalList = shouldFollowDiscard(
      shouldFollowMaxSizeInCamera,
      tempFilePaths,
      (list) {
        discardedFiles(list);
      },
      maxFileSize,
    );
    return Future.value(finalList);
  }

  Future<List<File>> pickFromAssets({
    required ValueNotifier<List<File>> filePaths,
    required int maxLength,
    required Function(List<File>) discardedFiles,
    required int maxFileSize,
    required bool shouldFollowMaxSizeInAssets,
  }) async {
    List<AssetEntity> assetFiles = await fetchImagesAssets(
      filePaths: filePaths,
      maxLength: maxLength,
    );
    List<List<AssetEntity>> separationList = separationFunction(assetFiles);
    List<AssetEntity> imagesList = separationList[0];
    List<AssetEntity> videosList = separationList[1];
    List<CroppedFile> croppedPaths = await assetImgToCroppedFiles(
      assetFiles: imagesList,
    );
    List<File> tempFilePaths = await croppedFilesToFiles(
      croppedPaths: croppedPaths,
    );
    List<File> temp = await assetVideosToFiles(assetFiles: videosList);
    tempFilePaths.addAll(temp);
    List<File> finalList = shouldFollowDiscard(
      shouldFollowMaxSizeInAssets,
      tempFilePaths,
      (list) {
        discardedFiles(list);
      },
      maxFileSize,
    );
    return Future.value(finalList);
  }

  List<List<AssetEntity>> separationFunction(
    dynamic item,
  ) {
    List<AssetEntity> imagesList = [];
    List<AssetEntity> videosList = [];
    if (item is AssetEntity) {
      if (item.type == AssetType.image) {
        imagesList.add(item);
      } else if (item.type == AssetType.video) {
        videosList.add(item);
      } else {
        log("Error in item is AssetEntity");
      }
    } else if (item is List<AssetEntity>) {
      for (var element in item) {
        if (element.type == AssetType.image) {
          imagesList.add(element);
        } else if (element.type == AssetType.video) {
          videosList.add(element);
        } else {
          log("Error in item is List<AssetEntity>");
        }
      }
    } else {
      log("Error in separationFunction item");
    }
    return [imagesList, videosList];
  }

  Future<AssetEntity> fetchImagesFromCamera() async {
    AssetEntity tempAssetEntity = const AssetEntity(
      id: "0",
      typeInt: 0,
      width: 0,
      height: 0,
    );
    try {
      tempAssetEntity = await CameraPicker.pickFromCamera(
            ctx,
            locale: Localizations.localeOf(ctx),
            pickerConfig: CameraPickerConfig(
              textDelegate: const EnglishCameraPickerTextDelegate(),
              imageFormatGroup: ImageFormatGroup.jpeg,
              shouldDeletePreviewFile: true,
              enableRecording: false,
              onError: (object, stackTrace) {
                log('onError object : ${object.toString()}');
                log('onError stackTrace : ${stackTrace.toString()}');
              },
            ),
          ) ??
          const AssetEntity(
            id: "0",
            typeInt: 0,
            width: 0,
            height: 0,
          );
    } catch (e) {
      log('Unable to fetch image from camera : ${e.toString()}');
    }
    return Future.value(tempAssetEntity);
  }

  Future<List<AssetEntity>> fetchImagesAssets({
    required ValueNotifier<List<File>> filePaths,
    required int maxLength,
  }) async {
    List<AssetEntity> tempAssetEntity = [];
    try {
      tempAssetEntity = await AssetPicker.pickAssets(
            ctx,
            pickerConfig: AssetPickerConfig(
              maxAssets: (maxLength - filePaths.value.length),
              textDelegate: const EnglishAssetPickerTextDelegate(),
              requestType: RequestType.common,
              limitedPermissionOverlayPredicate: (PermissionState state) {
                log("limitedPermissionOverlayPredicate : $state");
                return false;
              },
              loadingIndicatorBuilder: (context, isAssetsEmpty) {
                return isAssetsEmpty
                    ? const Text(
                        'Assets are unavailable, try adding assets.',
                      )
                    : Platform.isIOS
                        ? const CupertinoActivityIndicator()
                        : Platform.isAndroid
                            ? const CircularProgressIndicator()
                            : const Text(
                                'Assets are loading...',
                              );
              },
            ),
          ) ??
          [];
    } catch (e) {
      log('Unable to fetch image from asset : ${e.toString()}');
    }
    return Future.value(tempAssetEntity);
  }

  Future<List<CroppedFile>> assetImgToCroppedFiles({
    required List<AssetEntity> assetFiles,
  }) async {
    List<CroppedFile> tempCroppedList = [];
    await Future.forEach(
      assetFiles,
      (AssetEntity item) async {
        File normalFile = await item.file ?? File("");
        CroppedFile croppedFile = await cropImage(file: normalFile);
        tempCroppedList.add(croppedFile);
      },
    );
    return Future.value(tempCroppedList);
  }

  Future<CroppedFile> cropImage({
    required File file,
  }) async {
    CroppedFile tempCroppedFile = await ImageCropper.platform.cropImage(
          sourcePath: file.path,
          cropStyle: CropStyle.rectangle,
          compressFormat: ImageCompressFormat.png,
          compressQuality: 100,
        ) ??
        CroppedFile("");
    return Future.value(tempCroppedFile);
  }

  Future<List<File>> croppedFilesToFiles({
    required List<CroppedFile> croppedPaths,
  }) async {
    List<File> tempFileList = [];
    for (var element in croppedPaths) {
      tempFileList.add(File(element.path));
    }
    return Future.value(tempFileList);
  }

  Future<List<File>> assetVideosToFiles({
    required List<AssetEntity> assetFiles,
  }) async {
    List<File> temp = [];
    await Future.forEach(
      assetFiles,
      (AssetEntity item) async {
        File normalFile = await item.file ?? File("");
        temp.add(normalFile);
      },
    );
    return Future.value(temp);
  }

  List<List<File>> discardFunction(
    List<File> tempFilePaths,
    int maxFileSize,
  ) {
    List<File> keepFilesList = [];
    List<File> discardedFilesList = [];
    for (var element in tempFilePaths) {
      element.lengthSync() < maxFileSize
          ? keepFilesList.add(element)
          : discardedFilesList.add(element);
    }
    return [keepFilesList, discardedFilesList];
  }

  List<File> shouldFollowDiscard(
    bool shouldFollow,
    List<File> tempFilePaths,
    Function(List<File>) discardedFiles,
    int maxFileSize,
  ) {
    tempFilePaths.removeWhere((element) => element.path == "");
    if (shouldFollow) {
      List<File> keepFilesList = [];
      List<File> discardedFilesList = [];
      List<List<File>> keepAndDiscardList = discardFunction(
        tempFilePaths,
        maxFileSize,
      );
      keepFilesList = keepAndDiscardList[0];
      discardedFilesList = keepAndDiscardList[1];
      discardedFiles(discardedFilesList);
      return keepFilesList;
    } else {
      return tempFilePaths;
    }
  }

  Future<File> generateThumbnailForVideo({
    required String path,
  }) async {
    String data = "";
    try {
      data = await thumbnail.VideoThumbnail.thumbnailFile(
            video: path,
            thumbnailPath: (await getTemporaryDirectory()).path,
            imageFormat: thumbnail.ImageFormat.PNG,
            quality: 100,
            maxHeight: MediaQuery.of(ctx).size.height.toInt(),
            maxWidth: MediaQuery.of(ctx).size.width.toInt(),
          ) ??
          "";
    } catch (e) {
      log('Unable to fetch thumbnail : ${e.toString()}');
    }
    return Future.value(File(data));
  }
}
