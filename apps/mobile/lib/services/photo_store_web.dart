import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Browser simulator keeps uploaded photos in memory for the current session.
class PhotoRecord {
  const PhotoRecord(this.data);
  final Uint8List data;
  ImageProvider get provider => MemoryImage(data);
  Future<Uint8List> bytes() async => data;
}

Future<List<PhotoRecord>> loadPhotos() async => [];
Future<PhotoRecord> savePhoto(Uint8List bytes) async => PhotoRecord(bytes);
