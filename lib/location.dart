import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key});

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  GoogleMapController? _mapController;
  Position? _currentPosition;
  static const String apiKey = "AIzaSyDAGsVp0FWyZdYBoB_TG54QyTZwPjet7-M";
  LatLng _initialPosition = const LatLng(37.4219999, -122.0840575);
  Marker? _selectedMarker;
  List<Polyline> _routePolylines = [];
  String _durationText = '';
  TextEditingController _searchController = TextEditingController();
  List<dynamic> _searchSuggestions = [];

  @override
  void initState() {
    super.initState();
    _checkPermissionsAndLocationService();
  }

  Future<void> _checkPermissionsAndLocationService() async {
    if (!(await Geolocator.isLocationServiceEnabled())) {
      _showErrorSnackBar('Location services are disabled.');
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    _startLocationUpdates();
  }

  void _startLocationUpdates() {
    Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10))
        .listen((Position position) {
      setState(() {
        _currentPosition = position;
        _mapController?.animateCamera(CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude)));
        if (_selectedMarker != null) {
          _drawRoutePolyline(LatLng(position.latitude, position.longitude), _selectedMarker!.position);
        }
      });
    });
  }

  Future<List<dynamic>> _searchPlaces(String query) async {
    final response = await http.get(Uri.parse(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$query&key=$apiKey'));
    return response.statusCode == 200 ? jsonDecode(response.body)['predictions'] : [];
  }

  Future<LatLng?> _getPlaceLocation(String placeId) async {
    final response = await http.get(Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&key=$apiKey'));
    if (response.statusCode == 200) {
      final location = jsonDecode(response.body)['result']['geometry']['location'];
      return LatLng(location['lat'], location['lng']);
    }
    return null;
  }

  Future<String?> _getAddressFromLatLng(LatLng position) async {
    final response = await http.get(Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?latlng=${position.latitude},${position.longitude}&key=$apiKey'));
    if (response.statusCode == 200) {
      final results = jsonDecode(response.body)['results'];
      return results.isNotEmpty ? results.firstWhere((res) => !RegExp(r'^[A-Z0-9]+\+').hasMatch(res['formatted_address']), orElse: () => null)['formatted_address'] : null;
    }
    return null;
  }

  Future<void> _drawRoutePolyline(LatLng start, LatLng destination, {List<LatLng> waypoints = const []}) async {
    String waypointsString = waypoints.map((point) => '${point.latitude},${point.longitude}').join('|');
    final response = await http.get(Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json?origin=${start.latitude},${start.longitude}&destination=${destination.latitude},${destination.longitude}&waypoints=$waypointsString&mode=driving&departure_time=now&traffic_model=best_guess&key=$apiKey&extraComputations=TRAFFIC_ON_POLYLINE&routingPreference=TRAFFIC_AWARE_OPTIMAL'));

    if (response.statusCode == 200) {
      final route = jsonDecode(response.body)['routes'][0];
      final durationInTraffic = route['legs'][0]['duration_in_traffic']['text'];
      _createPolyline(route);
      setState(() {
        _durationText = 'Estimated time: $durationInTraffic';
        _selectedMarker = Marker(markerId: const MarkerId("selected_location"), position: destination);
      });
    }
  }


  void _createPolyline(Map<String, dynamic> route) {
    List<Polyline> polylines = [];
    var leg = route['legs'][0];  // Get the first leg

    // Extract total leg duration and duration_in_traffic
    int legDuration = leg['duration']['value'];
    int legDurationInTraffic = leg.containsKey('duration_in_traffic')
        ? leg['duration_in_traffic']['value']
        : legDuration;

    // Calculate a ratio of traffic for the leg
    double trafficRatio = legDurationInTraffic / legDuration;

    // Loop through the steps and calculate traffic for each step
    for (var step in leg['steps']) {
      final points = _decodePolyline(step['polyline']['points']);

      int stepDuration = step['duration']['value'];

      // Estimate traffic duration for the step
      int estimatedStepDurationInTraffic = (stepDuration * trafficRatio).toInt();

      // Determine the color for this step based on the estimated traffic
      Color stepColor = estimatedStepDurationInTraffic > stepDuration * 1.5
          ? Colors.red
          : (estimatedStepDurationInTraffic > stepDuration * 1.2
          ? Colors.orange
          : Colors.green);

      // Add the polyline with the step-specific color
      polylines.add(Polyline(
        polylineId: PolylineId("route_step_${polylines.length}"),
        points: points,
        color: stepColor,  // Dynamic color based on traffic
        width: 5,
      ));
    }

    setState(() => _routePolylines = polylines);
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> polyline = [];
    int index = 0, lat = 0, lng = 0;
    while (index < encoded.length) {
      int result = 0, shift = 0, b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      shift = result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      polyline.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return polyline;
  }

  void _onMapTapped(LatLng position) async {
    var places = await _fetchNearbyPlaces(position);
    setState(() {
      _selectedMarker = Marker(markerId: const MarkerId("selected_location"), position: position);
      if (_currentPosition != null) _drawRoutePolyline(LatLng(_currentPosition!.latitude, _currentPosition!.longitude), position);
    });
    String? address = await _getAddressFromLatLng(position);
    setState(() => _searchController.text = address ?? "${position.latitude}, ${position.longitude}");
    _searchSuggestions.clear();

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

  //// Photo

  Future<List<dynamic>> _fetchNearbyPlaces(LatLng location) async {
    final String url =
        'https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=${location.latitude},${location.longitude}&radius=500&key=$apiKey';

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

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Google Maps Location')),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _initialPosition, zoom: 14.0),
            markers: _selectedMarker != null ? {_selectedMarker!} : {},
            polylines: Set<Polyline>.of(_routePolylines),
            trafficEnabled: true,
            onMapCreated: (controller) => _mapController = controller,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            onTap: _onMapTapped,
          ),
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Column(
              children: [
                _buildSearchField(),
                if (_searchSuggestions.isNotEmpty) _buildSuggestionsList(),
              ],
            ),
          ),
          if (_durationText.isNotEmpty)
            Positioned(
              bottom: 20,
              left: 15,
              right: 55,
              child: Container(padding: const EdgeInsets.all(10), color: Colors.white, child: Text(_durationText)),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 5)]),
      child: TextField(
        controller: _searchController,
        onChanged: (query) async {
          if (query.isNotEmpty) {
            final suggestions = await _searchPlaces(query);
            setState(() => _searchSuggestions = suggestions);
          } else {
            setState(() => _searchSuggestions = []);
          }
        },
        decoration: const InputDecoration(hintText: 'Search a place...', border: InputBorder.none, suffixIcon: Icon(Icons.search)),
      ),
    );
  }

  Widget _buildSuggestionsList() {
    return Container(
      margin: const EdgeInsets.only(top: 5),
      color: Colors.white,
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _searchSuggestions.length,
        itemBuilder: (context, index) {
          final suggestion = _searchSuggestions[index];
          return ListTile(
            title: Text(suggestion['description']),
            onTap: () async {
              LatLng? location = await _getPlaceLocation(suggestion['place_id']);
              if (location != null) {
                _mapController?.animateCamera(CameraUpdate.newLatLngZoom(location, 14.0));
                _onMapTapped(location);
              }
            },
          );
        },
      ),
    );
  }
}
