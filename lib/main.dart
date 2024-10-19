// main.dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:init_test/location.dart';
import 'package:init_test/location_photo.dart';
import 'package:init_test/notification.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await dotenv.load(fileName: ".env");
  runApp(MyApp());
}

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('Handling a background message: ${message.messageId}');
}


class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: HomeScreen(), // Home screen where the button is
    );
  }
}

class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home Screen'),
      ),
      body: Center(
        child: Column(
          children: [
            ElevatedButton(
              onPressed: () {
                // Navigate to the notification screen when pressed
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => NotificationScreen()),
                );
              },
              child: const Text('Go to Notification Screen'),
            ),
            ElevatedButton(
              onPressed: () {
                // Navigate to the notification screen when pressed
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const LocationScreen()),
                );
              },
              child: const Text('Go to Location Screen'),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {
                // Navigate to the notification screen when pressed
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const LocationPhotoScreen()),
                );
              },
              child: const Text('picture on map'),
            ),
          ],
        ),
      ),
    );
  }
}
