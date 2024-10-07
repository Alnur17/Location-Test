import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key});

  @override
  State<LocationScreen> createState() {
    return _LocationScreenState();
  }
}

class _LocationScreenState extends State<LocationScreen> {
  GoogleMapController? _mapController;
  Position? _currentPosition;
  static const String apiKey = "AIzaSyDAGsVp0FWyZdYBoB_TG54QyTZwPjet7-M";
  LatLng _initialPosition = const LatLng(37.4219999, -122.0840575); // Default position (Google HQ)
  Marker? _selectedMarker;
  List<Polyline> _routePolylines = [];
  String _durationText = '';
  TextEditingController _searchController = TextEditingController();
  List<dynamic> _searchSuggestions = []; // To store the search results

  @override
  void initState() {
    super.initState();
    _checkPermissionsAndLocationService();
  }

  Future<void> _checkPermissionsAndLocationService() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showErrorSnackBar('Location services are disabled.');
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showErrorSnackBar('Location permissions are denied.');
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _showErrorSnackBar('Location permissions are permanently denied.');
      return;
    }

    _startLocationUpdates();
  }

  void _startLocationUpdates() {
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((Position position) {
      setState(() {
        _currentPosition = position;
        _animateToUserPosition();

        // Update the polyline if there's a selected marker (destination)
        if (_selectedMarker != null) {
          _drawRoutePolyline(
            LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
            _selectedMarker!.position,
          );
        }
      });
    });
  }

  void _animateToUserPosition() {
    if (_mapController != null && _currentPosition != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLng(
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        ),
      );
    }
  }

  Future<List<dynamic>> _searchPlaces(String query) async {
    final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$query&key=$apiKey');

    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['predictions'];
    } else {
      _showErrorSnackBar('Failed to load place suggestions');
      return [];
    }
  }

  Future<LatLng?> _getPlaceLocation(String placeId) async {
    final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&key=$apiKey');

    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final location = data['result']['geometry']['location'];
      return LatLng(location['lat'], location['lng']);
    } else {
      _showErrorSnackBar('Failed to load place details');
      return null;
    }
  }

  void _onMapTapped(LatLng position) async {
    setState(() {
      _selectedMarker = Marker(
        markerId: const MarkerId("selected_location"),
        position: position,
        infoWindow: const InfoWindow(title: 'Selected Location'),
      );
      if (_currentPosition != null) {
        _drawRoutePolyline(
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          position,
        );
      }
      _animateToSelectedLocation(position);
    });

    // Get the address for the tapped location
    try {
      String? address = await _getAddressFromLatLng(position);

      // Debugging: Log the address or coordinate response
      print('Address: $address');

      if (address != null && address.isNotEmpty) {
        setState(() {
          _searchController.text = address; // Set the address in the search bar
        });
      } else {
        // If no address found, fallback to coordinates
        setState(() {
          _searchController.text = "${position.latitude}, ${position.longitude}";
        });
      }
    } catch (e) {
      // If reverse geocoding fails, log the error and fallback to coordinates
      print('Error reverse geocoding: $e');
      setState(() {
        _searchController.text = "${position.latitude}, ${position.longitude}";
      });
    }

    _searchSuggestions.clear(); // Close the search drawer
  }

  Future<String?> _getAddressFromLatLng(LatLng position) async {
    final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?latlng=${position.latitude},${position.longitude}&key=$apiKey');

    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      print('Geocode API Response: ${response.body}'); // Debugging print

      if (data['status'] == 'OK' && data['results'].isNotEmpty) {
        // Iterate over the results and find the first non-Plus Code address
        for (var result in data['results']) {
          final formattedAddress = result['formatted_address'];
          // Skip any addresses that start with a Plus Code (e.g., 'QC29+FF5')
          if (!RegExp(r'^[A-Z0-9]+\+').hasMatch(formattedAddress)) {
            return formattedAddress; // Return the first valid address without Plus Code
          }
        }
      } else {
        _showErrorSnackBar('No address found for this location');
        return null;
      }
    } else {
      _showErrorSnackBar('Failed to load address');
      return null;
    }
  }





  void _animateToSelectedLocation(LatLng position) {
    if (_mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(position, 16.0),
      );
    }
  }

  Future<void> _drawRoutePolyline(LatLng start, LatLng destination) async {
    final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json?origin=${start.latitude},${start.longitude}&destination=${destination.latitude},${destination.longitude}&mode=driving&departure_time=now&traffic_model=best_guess&key=$apiKey');

    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      if (data['status'] == 'OK') {
        final route = data['routes'][0];
        final durationInTraffic = route['legs'][0]['duration_in_traffic']['text'];

        _createPolyline(route);

        setState(() {
          _durationText = 'Estimated time by car: $durationInTraffic';
          _selectedMarker = Marker(
            markerId: const MarkerId("selected_location"),
            position: destination,
            infoWindow: InfoWindow(
              title: 'Selected Location',
              snippet: durationInTraffic,
            ),
          );
        });
      } else {
        _showErrorSnackBar("Error getting driving route: ${data['status']}");
      }
    } else {
      _showErrorSnackBar('Failed to load driving directions');
    }
  }

  void _createPolyline(Map<String, dynamic> route) {
    final legs = route['legs'][0]['steps'];
    List<Polyline> polylines = [];

    for (var i = 0; i < legs.length; i++) {
      final step = legs[i];
      final polyline = _decodePolyline(step['polyline']['points']);
      polylines.add(Polyline(
        polylineId: PolylineId("route_step_$i"),
        points: polyline,
        color: Colors.deepOrange,
        width: 5,
      ));
    }

    setState(() {
      _routePolylines = polylines;
    });
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> polyline = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      final point = LatLng(lat / 1E5, lng / 1E5);
      polyline.add(point);
    }
    return polyline;
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // When the search field input changes, fetch new place suggestions
  void _onSearchChanged(String query) async {
    if (query.isNotEmpty) {
      final suggestions = await _searchPlaces(query);
      setState(() {
        _searchSuggestions = suggestions;
      });
    } else {
      setState(() {
        _searchSuggestions = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Location on Google Maps'),
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _initialPosition,
              zoom: 14.0,
            ),
            markers: {
              if (_selectedMarker != null) _selectedMarker!,
            },
            polylines: Set<Polyline>.of(_routePolylines),
            trafficEnabled: true,
            onMapCreated: (GoogleMapController controller) {
              _mapController = controller;
            },
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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 5,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: const InputDecoration(
                      hintText: 'Search a place...',
                      border: InputBorder.none,
                      suffixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                if (_searchSuggestions.isNotEmpty)
                  Container(
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
                            final placeId = suggestion['place_id'];
                            final location = await _getPlaceLocation(placeId);
                            if (location != null) {
                              _onMapTapped(location);
                              // Update search text with selected place
                              _searchController.text = suggestion['description'];
                              _searchSuggestions.clear(); // Close the search drawer
                            }
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          if (_durationText.isNotEmpty)
            Positioned(
              bottom: 20,
              left: 15,
              right: 55,
              child: Container(
                padding: const EdgeInsets.all(10),
                color: Colors.white,
                child: Text(_durationText),
              ),
            ),
        ],
      ),
    );
  }
}
