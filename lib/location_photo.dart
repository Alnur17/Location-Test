import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class LocationPhotoScreen extends StatefulWidget {
  const LocationPhotoScreen({super.key});

  @override
  State<LocationPhotoScreen> createState() {
    return _LocationPhotoScreenState();
  }
}

class _LocationPhotoScreenState extends State<LocationPhotoScreen> {
  late GoogleMapController mapController;
  final String apiKey = dotenv.env['GOOGLE_MAP_APIKEY'] ?? '';
  final LatLng _initialPosition = const LatLng(37.7749, -122.4194); // Default to San Francisco

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nearby Places Photos')),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: _initialPosition,
          zoom: 12,
        ),
        onMapCreated: (controller) {
          mapController = controller;
        },
        onTap: _handleTap,
      ),
    );
  }

  void _handleTap(LatLng tappedPoint) async {
    // Fetch nearby places
    var places = await _fetchNearbyPlaces(tappedPoint);

    if (places.isNotEmpty) {
      // Show photos in a modal bottom sheet
      showModalBottomSheet(
        context: context,
        builder: (context) {
          return _buildPlacesPhotoGallery(places);
        },
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No places found')),
      );
    }
  }

  Future<List<dynamic>> _fetchNearbyPlaces(LatLng location) async {
    final String url =
        'https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=${location.latitude},${location.longitude}&radius=1500&key=$apiKey';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['results'];
    } else {
      throw Exception('Failed to load nearby places');
    }
  }

  Widget _buildPlacesPhotoGallery(List<dynamic> places) {
    List<String> photoUrls = [];

    // Get photo URLs from the places
    for (var place in places) {
      if (place['photos'] != null && place['photos'].isNotEmpty) {
        final String photoReference = place['photos'][0]['photo_reference'];
        final String photoUrl =
            'https://maps.googleapis.com/maps/api/place/photo?maxwidth=400&photoreference=$photoReference&key=$apiKey'; // Replace with your Google Places API key
        photoUrls.add(photoUrl);
      }
    }

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: photoUrls.isNotEmpty
          ? GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 4.0,
          mainAxisSpacing: 4.0,
        ),
        itemCount: photoUrls.length,
        itemBuilder: (context, index) {
          return Image.network(
            photoUrls[index],
            fit: BoxFit.cover,
          );
        },
      )
          : const Center(child: Text('No photos available')),
    );
  }
}
