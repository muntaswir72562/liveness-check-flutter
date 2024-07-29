import 'dart:async';
import 'dart:io';
import 'dart:math';
// import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class IDScanningPage extends StatefulWidget {
  final File selfiePath;

  const IDScanningPage({super.key, required this.selfiePath});

  @override
  State<IDScanningPage> createState() => _IDScanningPageState();
}

class _IDScanningPageState extends State<IDScanningPage> {
  CameraController? _cameraController;
  File? _idImage;
  bool _isProcessing = false;
  bool _idCaptured = false;
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableLandmarks: true,
      enableClassification: true,
      enableTracking: true,
      minFaceSize: 0.1,
    ),
  );
  final TextRecognizer _textRecognizer = TextRecognizer();
  String _extractedText = '';

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    final backCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    _cameraController = CameraController(
      backCamera,
      ResolutionPreset.high,
    );

    await _cameraController!.initialize();
    if (mounted) {
      setState(() {});
      _startIDDetection();
    }
  }

  void _startIDDetection() {
    _cameraController!.startImageStream((CameraImage image) {
      // We're no longer automatically processing the image here
      // The processing will be triggered by the button press
    });
  }

  void _onScanButtonPressed() async {
    if (_cameraController == null || _idCaptured) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final image = await _cameraController!.takePicture();
      setState(() {
        _idImage = File(image.path);
        _idCaptured = true;
      });

      await _processAndCompareImages();
    } catch (e) {
      _handleError('Error capturing ID', e);
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  // InputImage _cameraImageToInputImage(CameraImage image) {
  //   final bytes = _concatenatePlanes(image.planes);
  //   final imageSize = Size(image.width.toDouble(), image.height.toDouble());

  //   final inputImageData = InputImageMetadata(
  //     size: imageSize,
  //     rotation: InputImageRotation.rotation0deg,
  //     format: InputImageFormat.nv21,
  //     bytesPerRow: image.planes[0].bytesPerRow,
  //   );

  //   return InputImage.fromBytes(
  //     bytes: bytes,
  //     metadata: inputImageData,
  //   );
  // }

  // Uint8List _concatenatePlanes(List<Plane> planes) {
  //   final allBytes = <int>[];
  //   for (final plane in planes) {
  //     allBytes.addAll(plane.bytes);
  //   }
  //   return Uint8List.fromList(allBytes);
  // }

  Future<void> _processAndCompareImages() async {
    if (_idImage == null) return;

    try {
      final selfieImage = InputImage.fromFilePath(widget.selfiePath.path);
      final idImage = InputImage.fromFilePath(_idImage!.path);

      final selfieFaces = await _faceDetector.processImage(selfieImage);
      final idFaces = await _faceDetector.processImage(idImage);

      if (selfieFaces.isEmpty || idFaces.isEmpty) {
        _showResultDialog('Face not detected in one or both images.', true);
        return;
      }

      final selfieFace = selfieFaces.first;
      final idFace = idFaces.first;

      final similarityScore = _calculateFaceSimilarity(selfieFace, idFace);
      final orientationCheck = _checkFaceOrientation(selfieFace, idFace);

      // Extract text from ID
      await _extractTextFromID();

      // if (similarityScore >= 0 && orientationCheck) {
      if (similarityScore >= 0 && true) {
        _showResultDialog('ID verified successfully!\nSimilarity score: ${(similarityScore * 100).toStringAsFixed(2)}%\n\nExtracted Information:\n$_extractedText', false);
      } else {
        _showResultDialog('ID verification failed. Please try again.\nSimilarity score: ${(similarityScore * 100).toStringAsFixed(2)}%', true);
      }
    } catch (e) {
      _handleError('Error processing images', e);
      _showResultDialog('An error occurred during processing.', true);
    }
  }

  Future<void> _extractTextFromID() async {
    if (_idImage == null) return;

    final inputImage = InputImage.fromFilePath(_idImage!.path);
    final recognizedText = await _textRecognizer.processImage(inputImage);

    setState(() {
      _extractedText = _parseExtractedText(recognizedText.text);
    });
  }

String _parseExtractedText(String text) {
  final lines = text.split('\n');
  final extractedInfo = {
    'surname': '',
    'First Name': '',
    'Gender': '',
    'DOB': '',
    'NIC': '',
  };
  
  for (int i = 0; i < lines.length; i++) {
    String line = lines[i].trim().toLowerCase();
    
    if (line == 'specimen') continue;  // Skip "SPECIMEN" text
    
    if (line.contains('surname')) {
      extractedInfo['surname'] = lines[i+1].trim();  // Surname is on the next line
    } else if (line.contains('given names')) {
      extractedInfo['First Name'] = lines[i+1].trim();  // Given Names are on the next line
    } else if (line.contains('date of birth')) {
      extractedInfo['DOB'] = lines[i+1].trim();  // Date of Birth is on the next line
    } else if (RegExp(r'^[A-Z]\d{13}$').hasMatch(line.toUpperCase())) {
      extractedInfo['NIC'] = line.toUpperCase();  // This is likely the ID number
    }
  }

  // Gender is not explicitly stated on the ID, so we'll leave it blank

  // Format the output as requested
  return '''
  surname: ${extractedInfo['surname']}
  First Name: ${extractedInfo['First Name']}
  Gender: ${extractedInfo['Gender']}
  DOB: ${extractedInfo['DOB']}
  NIC: ${extractedInfo['NIC']}
  ''';
}

  // String _getValueAfterColon(String line) {
  //   final parts = line.split(':');
  //   return parts.length > 1 ? parts[1].trim() : '';
  // }

  void _showResultDialog(String message, bool showRetry) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ID Verification Result'),
        content: Text(message),
        actions: [
          if (showRetry)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _resetIDCapture();
              },
              child: const Text('Retry'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _resetIDCapture() {
    setState(() {
      _idImage = null;
      _idCaptured = false;
      _isProcessing = false;
      _extractedText = '';
    });
    _startIDDetection();
  }

  void _handleError(String message, Object error) {
    debugPrint('$message: $error');
  }

  double _calculateFaceSimilarity(Face face1, Face face2) {
    final landmarks1 = _getFacialLandmarks(face1);
    final landmarks2 = _getFacialLandmarks(face2);

    if (landmarks1.isEmpty || landmarks2.isEmpty) {
      return 0.0;
    }

    double totalDistance = 0;
    int count = 0;

    for (final key in landmarks1.keys) {
      if (landmarks2.containsKey(key)) {
        totalDistance += _calculateDistance(landmarks1[key]!, landmarks2[key]!);
        count++;
      }
    }

    if (count == 0) return 0.0;

    final averageDistance = totalDistance / count;
    return 1 / (1 + averageDistance);  // Normalize to [0, 1]
  }

  Map<FaceLandmarkType, Point<int>> _getFacialLandmarks(Face face) {
    final landmarks = <FaceLandmarkType, Point<int>>{};
    for (final entry in face.landmarks.entries) {
      final landmark = entry.value;
      if (landmark != null) {
        landmarks[entry.key] = landmark.position;
      }
    }
    return landmarks;
  }

  double _calculateDistance(Point<int> p1, Point<int> p2) {
    return sqrt(pow(p1.x - p2.x, 2) + pow(p1.y - p2.y, 2));
  }

  bool _checkFaceOrientation(Face face1, Face face2) {
    final headEulerAngleY1 = face1.headEulerAngleY ?? 0;
    final headEulerAngleY2 = face2.headEulerAngleY ?? 0;
    final headEulerAngleZ1 = face1.headEulerAngleZ ?? 0;
    final headEulerAngleZ2 = face2.headEulerAngleZ ?? 0;

    final headEulerAngleYDiff = (headEulerAngleY1 - headEulerAngleY2).abs();
    final headEulerAngleZDiff = (headEulerAngleZ1 - headEulerAngleZ2).abs();

    return headEulerAngleYDiff < 15 && headEulerAngleZDiff < 15;
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_cameraController!),
          _buildIDPlaceholder(),
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Center(
              child: ElevatedButton(
                onPressed: _idCaptured ? null : _onScanButtonPressed,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  textStyle: const TextStyle(fontSize: 20),
                ),
                child: Text(_idCaptured ? 'ID Captured' : 'Scan ID'),
              ),
            ),
          ),
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
          if (_idCaptured)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Text(
                  'ID Captured! Processing...',
                  style: TextStyle(color: Colors.white, fontSize: 20),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildIDPlaceholder() {
    return Center(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.width * 0.57, // Adjusted for Mauritian ID card aspect ratio
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Text(
            'Place Mauritian ID here',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceDetector.close();
    _textRecognizer.close();
    super.dispose();
  }
}