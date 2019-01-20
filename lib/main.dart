import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:translator/translator.dart';
import 'package:googleapis/vision/v1.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:io';
import 'dart:convert';

List<CameraDescription> cameras;

Future<void> main() async {
  cameras = await availableCameras();
  runApp(MyApp());
}

/// Returns a suitable camera icon for [direction].
IconData getCameraLensIcon(CameraLensDirection direction) {
  switch (direction) {
    case CameraLensDirection.back:
      return Icons.camera_rear;
    case CameraLensDirection.front:
      return Icons.camera_front;
    case CameraLensDirection.external:
      return Icons.camera;
  }
  throw ArgumentError('Unknown lens direction');
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Language Leap',
      theme: ThemeData(
        primarySwatch: Colors.teal,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: Text('Language Leap'),
        ),
        body: Center(
          child: MyHomePage(),
      ),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

void logError(String code, String message) =>
    print('Error: $code\nError Message: $message');

class _MyHomePageState extends State<MyHomePage> {
  int _score = 0;
  int _numWrong = 0;
  int _numRight = 0;
  String imagePath;
  String base64Image;
  String label;
  CameraController controller;

  void _onCorrect() {
    setState(() {
      _score += 50;
      _numRight++;
    });
  }

  void _onIncorrect() {
    setState(() {
      _numWrong++;
    });
  }

  @override
  void initState() {
    super.initState();
    controller = CameraController(cameras[0], ResolutionPreset.medium);
    controller.initialize().then((_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  void onTakePictureButtonPressed() {
    print('took a picture!');
    takePicture().then((String filePath) {
      if (mounted) {
        setState(() {
          imagePath = filePath;
        });
      }
    });

    if(imagePath != null)
      setState(() {
          base64Image = processImage(imagePath);
      });

    if(base64Image != null){
      classifyImage(base64Image).then((String responseBody){
        setState(() {
          label = responseBody;
          print("label $label");
        });
      });
    }
  }  

  Widget _cameraPreviewWidget() {
    if (controller == null || !controller.value.isInitialized) {
      return const Text(
        'Tap a camera',
        style: TextStyle(
          color: Colors.white,
          fontSize: 24.0,
          fontWeight: FontWeight.w900,
        ),
      );
    } else {
      return AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: CameraPreview(controller),
      );
    }
  }

  Widget _captureIcon() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      mainAxisSize: MainAxisSize.max,
      children: <Widget>[
        IconButton(
          icon: const Icon(Icons.camera_alt),
          color: Colors.blue,
          onPressed: controller != null &&
                  controller.value.isInitialized &&
                  !controller.value.isRecordingVideo
              ? onTakePictureButtonPressed
              : null,
        ),
      ],
    );
  }

  String timestamp() => DateTime.now().millisecondsSinceEpoch.toString();

  void _showCameraException(CameraException e) {
    logError(e.code, e.description);
  }

  void onNewCameraSelected(CameraDescription cameraDescription) async {
    if (controller != null) {
      await controller.dispose();
    }
    controller = CameraController(cameraDescription, ResolutionPreset.high);

    // If the controller is updated then update the UI.
    controller.addListener(() {
      if (mounted) setState(() {});
    });

    try {
      await controller.initialize();
    } on CameraException catch (e) {
      _showCameraException(e);
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<String> takePicture() async {
    if (!controller.value.isInitialized) {
      return null;
    }
    print('inside take picture function!');
    // final Directory extDir = await getTemporaryDirectory();
    // final String dirPath = '${extDir.path}/Pictures/flutter_test';
    // await Directory(dirPath).create(recursive: true);
    // final String filePath = '$dirPath/${timestamp()}.jpg';
    // print('path: $filePath');

    final Directory extDir = await getExternalStorageDirectory();
    final String dirPath = '${extDir.path}/Pictures/flutter_test';
    await Directory(dirPath).create(recursive: true);
    final String filePath = '$dirPath/${timestamp()}.jpg';
    print('path: $filePath');

    // final Directory extDir = await getApplicationDocumentsDirectory();
    // final String dirPath = '${extDir.path}/Pictures/flutter_test';
    // await Directory(dirPath).create(recursive: true);
    // final String filePath = '$dirPath/${timestamp()}.jpg';
    // print('path: $filePath');

    if (controller.value.isTakingPicture) {
      // A capture is already pending, do nothing.
      return null;
    }

    try {
      await controller.takePicture(filePath);
    } on CameraException catch (e) {
      _showCameraException(e);
      return null;
    }
    return filePath;
  }

  String processImage(String imagePath){
    File file = new File(imagePath);
      
    List<int> fileBytes = file.readAsBytesSync();
    print('filebytes: $fileBytes');
    String base64Image = base64Encode(fileBytes);
    print('base64 $base64Image');
    return base64Image;
  }

  Future<String> classifyImage(String base64Image) async{

    String googleVisionEndpoint = "https://vision.googleapis.com/v1/images:annotate?key=AIzaSyDKVljgt5f4I2dFcALCtwRBlRVnBCbHvy8";
    Map map = {
      "requests" : [
          {
            "image" : {
              "content" : base64Image
            },
            "features": [
              {
                "type" : "LABEL_DETECTION",
                "maxResults" : 1
              }
            ]
          }
        ]
      };
    
    HttpClient httpClient = new HttpClient();
    HttpClientRequest request = await httpClient.postUrl(Uri.parse(googleVisionEndpoint));

    request.headers.set('content-type', 'application/json');
    request.add(utf8.encode(json.encode(map)));

    HttpClientResponse response = await request.close();
    // todo - you should check the response.statusCode
    String reply = await response.transform(utf8.decoder).join();
    httpClient.close();

    List responseData = jsonDecode(reply);

    return responseData[1];
  }

  Widget camera() {
    return Scaffold(
      body: Column(
        children: <Widget>[
          Expanded(
            child: Container(
              child: Padding(
                padding: const EdgeInsets.all(1.0),
                child: Center(
                  child: _cameraPreviewWidget(),
                ),
              ),
              decoration: BoxDecoration(
                color: Colors.black,
                border: Border.all(
                  color: controller != null && controller.value.isRecordingVideo
                      ? Colors.redAccent
                      : Colors.grey,
                  width: 3.0,
                ),
              ),
            ),
          ),
          _captureIcon(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    'Score: $_score   Wrong: $_numWrong   Right: $_numRight',
                    style: Theme.of(context).textTheme.title,
                  ),
                )
              ]
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.max,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: controller.value.isInitialized == false
                  ? Container()
                  : Container(
                    height: 300.0,
                    width: 300.0,
                    child: AspectRatio(
                      aspectRatio: controller.value.aspectRatio,
                      child: camera(),
                    ),
                  ),
                ),
              ]
            ),
          ],
        ),
      ),
    );
  }
}
