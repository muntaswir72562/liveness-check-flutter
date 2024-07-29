import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'id_scanning_page.dart';

class LivenessDetectionPage extends StatefulWidget {
  const LivenessDetectionPage({super.key});

  @override
  State<LivenessDetectionPage> createState() => _LivenessDetectionPageState();
}

class _LivenessDetectionPageState extends State<LivenessDetectionPage> with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  FaceDetector? _faceDetector;
  bool _isDetecting = false;
  String _instruction = "Place your face in the circle";
  final List<String> _challenges = ['Blink both eyes', 'Smile', 'Turn Left', 'Turn Right'];
  String _currentChallenge = '';
  int _challengeIndex = -1; // Start at -1 to represent the initial face placement step
  Timer? _challengeTimer;
  int _timeRemaining = 10;
  late AnimationController _animationController;
  late Animation<double> _animation;
  double _progress = 0.0; // Track overall progress

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        minFaceSize: 0.1,
      ),
    );
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );
    _animation = Tween<double>(begin: 0, end: 1).animate(_animationController)
      ..addListener(() {
        setState(() {});
      });
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    final frontCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    _cameraController = CameraController(
      frontCamera,
      ResolutionPreset.medium,
    );

    await _cameraController!.initialize();
    if (!mounted) return;

    _cameraController!.startImageStream(_processCameraImage);
    setState(() {});
  }

  void _startNextChallenge() {
    _challengeIndex++;
    if (_challengeIndex >= _challenges.length) {
      setState(() {
        _instruction = "Liveness check passed!";
        _progress = 1.0; // Completed all challenges
      });
      return;
    }

    _currentChallenge = _challenges[_challengeIndex];
    _timeRemaining = 10;
    _animationController.reset();
    _animationController.forward();

    setState(() {
      _instruction = "Please $_currentChallenge";
    });

    _challengeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timeRemaining > 0) {
        setState(() {
          _timeRemaining--;
        });
      } else {
        _failChallenge();
      }
    });
  }

  void _failChallenge() {
    _challengeTimer?.cancel();
    _animationController.stop();
    setState(() {
      _instruction = "Challenge failed. Please try again.";
    });
    Future.delayed(const Duration(seconds: 2), () {
      _startNextChallenge();
    });
  }

  void _completeChallenge() {
    _challengeTimer?.cancel();
    _animationController.stop();
    setState(() {
      _progress = (_challengeIndex + 1) / _challenges.length;
    });
    if (_challengeIndex >= _challenges.length - 1) {
      // All challenges completed, navigate to ID scanning
      _navigateToIDScanning();
    } else {
      _startNextChallenge();
    }
  }

  void _navigateToIDScanning() async {
      final XFile selfieImage = await _cameraController!.takePicture();
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => IDScanningPage(selfiePath: File(selfieImage.path)),
        ),
      );
    }
  Future<void> _processCameraImage(CameraImage image) async {
    if (_isDetecting) return;
    _isDetecting = true;

    try {
      final inputImage = await _convertCameraImageToInputImage(image);
      if (inputImage == null) {
        _isDetecting = false;
        return;
      }

      final faces = await _faceDetector!.processImage(inputImage);

      if (faces.isNotEmpty) {
        final face = faces.first;
        if (_challengeIndex == -1) {
          // Initial face placement step
          _startNextChallenge(); // Automatically start the first challenge
        } else {
          _checkChallenge(face);
        }
      }
    } catch (e) {
      debugPrint('Error processing image: $e');
    } finally {
      _isDetecting = false;
    }
  }

  Future<InputImage?> _convertCameraImageToInputImage(CameraImage image) async {
    final allBytes = image.planes.fold<List<int>>([], (previousValue, plane) {
      previousValue.addAll(plane.bytes);
      return previousValue;
    });
    final bytes = Uint8List.fromList(allBytes);

    final imageSize = Size(image.width.toDouble(), image.height.toDouble());

    const imageRotation = InputImageRotation.rotation0deg;
    final inputImageFormat = InputImageFormatValue.fromRawValue(image.format.raw) ?? InputImageFormat.nv21;

    final inputImageData = InputImageMetadata(
      size: imageSize,
      rotation: imageRotation,
      format: inputImageFormat,
      bytesPerRow: image.planes[0].bytesPerRow,
    );

    return InputImage.fromBytes(bytes: bytes, metadata: inputImageData);
  }

  void _checkChallenge(Face face) {
    switch (_currentChallenge) {
      case 'Blink both eyes':
        if (face.leftEyeOpenProbability != null &&
            face.rightEyeOpenProbability != null &&
            face.leftEyeOpenProbability! < 0.1 &&
            face.rightEyeOpenProbability! < 0.1) {
          _completeChallenge();
        }
        break;
      case 'Smile':
        if (face.smilingProbability != null && face.smilingProbability! > 0.8) {
          _completeChallenge();
        }
        break;
      case 'Turn Left':
        if (face.headEulerAngleY != null && face.headEulerAngleY! < -30) {
          _completeChallenge();
        }
        break;
      case 'Turn Right':
        if (face.headEulerAngleY != null && face.headEulerAngleY! > 30) {
          _completeChallenge();
        }
        break;
    }
  }
  

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Center(
                    child: ClipOval(
                      child: SizedBox(
                        width: MediaQuery.of(context).size.width * 0.8,
                        height: MediaQuery.of(context).size.width * 0.8,
                        child: CameraPreview(_cameraController!),
                      ),
                    ),
                  ),
                  Center(
                    child: SizedBox(
                      width: MediaQuery.of(context).size.width * 0.85,
                      height: MediaQuery.of(context).size.width * 0.85,
                      child: CircularProgressIndicator(
                        value: _progress,
                        strokeWidth: 5,
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                _instruction,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceDetector?.close();
    _challengeTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }
}