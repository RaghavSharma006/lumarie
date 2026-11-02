import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PhotoRecord {
  const PhotoRecord(this.path);
  final String path;
  ImageProvider get provider => FileImage(File(path));
  Future<Uint8List> bytes() => File(path).readAsBytes();
}

Future<List<PhotoRecord>> loadPhotos() async {
  final prefs = await SharedPreferences.getInstance();
  return [
    for (final path in prefs.getStringList('photos') ?? <String>[])
      if (await File(path).exists()) PhotoRecord(path)
  ];
}

Future<PhotoRecord> savePhoto(Uint8List bytes) async {
  final dir = await getApplicationDocumentsDirectory();
  final path = '${dir.path}/photo_${DateTime.now().microsecondsSinceEpoch}.jpg';
  await File(path).writeAsBytes(bytes, flush: true);
  final prefs = await SharedPreferences.getInstance();
  await prefs
      .setStringList('photos', [path, ...?prefs.getStringList('photos')]);
  return PhotoRecord(path);
}
