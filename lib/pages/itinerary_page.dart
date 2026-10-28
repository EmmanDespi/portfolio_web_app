import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_html/html.dart' as html;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:portfolio/utils/app_theme.dart';
// NOTE: WireFrame, AppResponsive, AppColors and the `context.screenWidth`
// extension come from your project; add their imports if they live in other files.

const int _maxIndent = 4;

// ─────────────────────────── Data models ───────────────────────────

class ChecklistItem {
  ChecklistItem({
    String text = '',
    this.done = false,
    this.indent = 0,
    this.lat,
    this.lng,
    this.locationName = '',
  })  : controller = TextEditingController(text: text),
        locationController = TextEditingController(text: locationName),
        focus = FocusNode();

  factory ChecklistItem.fromJson(Map<String, dynamic> j) {
    final rawIndent = j['indent'];
    return ChecklistItem(
      text: (j['text'] ?? '').toString(),
      done: j['done'] == true,
      indent: rawIndent is num ? rawIndent.toInt().clamp(0, _maxIndent) : 0,
      lat: j['lat'] as double?,
      lng: j['lng'] as double?,
      locationName: (j['locationName'] ?? '').toString(),
    );
  }

  bool done;
  int indent;
  double? lat;
  double? lng;
  String locationName;
  final TextEditingController controller;
  final TextEditingController locationController;
  final FocusNode focus;

  Map<String, dynamic> toJson() => {
        'text': controller.text,
        'done': done,
        'indent': indent,
        'lat': lat,
        'lng': lng,
        'locationName': locationController.text,
      };

  void dispose() {
    controller.dispose();
    locationController.dispose();
    focus.dispose();
  }
}

void _fixIndents(List<ChecklistItem> items) {
  for (var i = 0; i < items.length; i++) {
    items[i].indent = i == 0
        ? 0
        : math.min(items[i].indent.clamp(0, _maxIndent), items[i - 1].indent + 1);
  }
}

class DayEntry {
  DayEntry({
    String title = '',
    String notes = '',
    List<ChecklistItem>? items,
    this.isMinimized = false,
  })  : titleController = TextEditingController(text: title),
        notesController = TextEditingController(text: notes),
        items = (items == null || items.isEmpty) ? [ChecklistItem()] : items;

  final TextEditingController titleController;
  final TextEditingController notesController;
  final List<ChecklistItem> items;
  
  bool isMinimized;

  void dispose() {
    titleController.dispose();
    notesController.dispose();
    for (final i in items) {
      i.dispose();
    }
  }
}

// ─────────────────────────── CSV Serialization (with Item Location) ───────────────────────────

class _ImportResult {
  _ImportResult(this.title, this.days);
  final String title;
  final List<DayEntry> days;
}

class ItineraryCodec {
  ItineraryCodec._();

  static String _field(String s) {
    final needsQuotes = s.contains(',') ||
        s.contains('"') ||
        s.contains('\n') ||
        s.contains('\r');
    return needsQuotes ? '"${s.replaceAll('"', '""')}"' : s;
  }

  static String toCsvString(String title, List<DayEntry> days) {
    final lines = <String>['T,${_field(title)}'];
    for (final d in days) {
      lines.add('D,${_field(d.titleController.text)},${_field(d.notesController.text)}');
      for (final i in d.items) {
        final latStr = i.lat?.toString() ?? '';
        final lngStr = i.lng?.toString() ?? '';
        lines.add('I,${_field(i.controller.text)},${i.done ? 1 : 0},${i.indent},$latStr,$lngStr,${_field(i.locationController.text)}');
      }
    }
    return lines.join('\n');
  }

  static _ImportResult parseCsv(String raw) {
    var text = raw;
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    final trimmed = text.trim();
    if (trimmed.isEmpty) throw const FormatException('Empty CSV');

    final rows = _splitCsv(trimmed);

    var title = '';
    var recognised = false;
    final days = <DayEntry>[];

    String? dayTitle;
    var dayNotes = '';
    var items = <ChecklistItem>[];

    void flushDay() {
      if (dayTitle == null) return;
      _fixIndents(items);
      days.add(DayEntry(
        title: dayTitle!,
        notes: dayNotes,
        items: items,
      ));
      dayTitle = null;
      dayNotes = '';
      items = <ChecklistItem>[];
    }

    String col(List<String> r, int i) => i < r.length ? r[i] : '';

    for (final r in rows) {
      if (r.isEmpty) continue;
      switch (r.first) {
        case 'T':
          title = col(r, 1);
          recognised = true;
          break;
        case 'D':
          flushDay();
          dayTitle = col(r, 1);
          dayNotes = col(r, 2);
          recognised = true;
          break;
        case 'I':
          dayTitle ??= '';
          items.add(ChecklistItem(
            text: col(r, 1),
            done: col(r, 2) == '1',
            indent: (int.tryParse(col(r, 3)) ?? 0).clamp(0, _maxIndent),
            lat: double.tryParse(col(r, 4)),
            lng: double.tryParse(col(r, 5)),
            locationName: col(r, 6),
          ));
          recognised = true;
          break;
        default:
          break;
      }
    }
    flushDay();

    if (!recognised) throw const FormatException('No valid itinerary CSV rows found');
    return _ImportResult(title, days);
  }

  static List<List<String>> _splitCsv(String input) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;

    void endRow() {
      row.add(field.toString());
      field.clear();
      final blank = row.length == 1 && row.first.isEmpty;
      if (!blank) rows.add(row);
      row = <String>[];
    }

    for (var i = 0; i < input.length; i++) {
      final c = input[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < input.length && input[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(c);
        }
      } else if (c == '"' && field.isEmpty) {
        inQuotes = true;
      } else if (c == ',') {
        row.add(field.toString());
        field.clear();
      } else if (c == '\n' || c == '\r') {
        if (c == '\r' && i + 1 < input.length && input[i + 1] == '\n') i++;
        endRow();
      } else {
        field.write(c);
      }
    }
    if (field.isNotEmpty || row.isNotEmpty) endRow();
    return rows;
  }
}

// ─────────────────────────── Page ───────────────────────────

class ItineraryPage extends StatefulWidget {
  const ItineraryPage({super.key});

  @override
  State<ItineraryPage> createState() => _ItineraryPageState();
}

class _ItineraryPageState extends State<ItineraryPage> {
  bool _isDark = false;
  bool _showMap = true;
  bool _showOptions = false;

  final TextEditingController _titleController = TextEditingController();
  final List<DayEntry> _days = [DayEntry(title: 'Day 1')];

  final MapController _mainMapController = MapController();
  LatLng _mapCenter = const LatLng(35.6762, 139.6503); // Default Tokyo
  double _mapZoom = 6.0;

  final ThemeData _lightTheme = AppTheme.portfolio(isDark: false);
  final ThemeData _darkTheme = AppTheme.portfolio(isDark: true);

  ThemeData get _theme => _isDark ? _darkTheme : _lightTheme;
  AppPalette get _p => _theme.extension<AppPalette>()!;

  Border get _border => Border.all(color: _p.ink, width: 2);

  BoxShadow _hardShadow(double offset) =>
      BoxShadow(color: _p.shadow, offset: Offset(offset, offset), blurRadius: 0);

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _promptDestinationOnLoad();
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    for (final d in _days) {
      d.dispose();
    }
    super.dispose();
  }

  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _isDark = prefs.getBool('isDark') ?? false);
  }

  Widget _menuItem({
    required IconData icon,
    required String label,
    required String route,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 2.5,
        ),
      ),
      onTap: () => context.go(route),
    );
  }

  Future<void> _promptDestinationOnLoad() async {
    final searchController = TextEditingController();
    List<Map<String, dynamic>> searchResults = [];
    bool isSearching = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> searchCountry(String query) async {
            if (query.trim().isEmpty) return;
            setDialogState(() => isSearching = true);
            try {
              final url = Uri.parse(
                  'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=5');
              final response = await http.get(url, headers: {'User-Agent': 'FlutterItineraryApp'});
              if (response.statusCode == 200) {
                final List data = jsonDecode(response.body);
                setDialogState(() {
                  searchResults = data.cast<Map<String, dynamic>>();
                });
              }
            } catch (_) {}
            setDialogState(() => isSearching = false);
          }

          return AlertDialog(
            backgroundColor: _p.card,
            title: Text('Where are you traveling to?', style: TextStyle(color: _p.ink)),
            content: SizedBox(
              width: AppResponsive.isDesktop(context) ? context.screenWidth * 0.4 : context.screenWidth * 95,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Enter a country, city, or destination to focus your map:', style: TextStyle(color: _p.ink)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: searchController,
                          autofocus: true,
                          style: TextStyle(color: _p.ink),
                          decoration: InputDecoration(
                            hintText: 'e.g., Japan, Paris, Philippines…',
                            hintStyle: TextStyle(color: _p.ink.withOpacity(0.4)),
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (val) => searchCountry(val),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: isSearching ? null : () => searchCountry(searchController.text),
                        child: isSearching
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text('Search', style: TextStyle(color: _p.paper)),
                      ),
                    ],
                  ),
                  if (searchResults.isNotEmpty)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 180),
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: searchResults.length,
                        itemBuilder: (context, index) {
                          final place = searchResults[index];
                          final displayName = place['display_name'] ?? '';
                          return ListTile(
                            dense: true,
                            title: Text(displayName, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: _p.ink)),
                            onTap: () {
                              final lat = double.parse(place['lat']);
                              final lon = double.parse(place['lon']);
                              final targetPoint = LatLng(lat, lon);

                              setState(() {
                                _mapCenter = targetPoint;
                                _mapZoom = 6.0;
                                if (_titleController.text.isEmpty) {
                                  _titleController.text = displayName.split(',').first;
                                }
                              });

                              _mainMapController.move(targetPoint, _mapZoom);
                              Navigator.pop(ctx);
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Skip', style: TextStyle(color: _p.ink)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _addDay() {
    setState(() => _days.add(DayEntry(title: 'Day ${_days.length + 1}')));
  }

  void _removeDay(DayEntry day) {
    setState(() => _days.remove(day));
    WidgetsBinding.instance.addPostFrameCallback((_) => day.dispose());
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  void _focusMapOnItem(ChecklistItem item) {
    if (item.lat != null && item.lng != null) {
      setState(() {
        _showMap = true;
        _mapCenter = LatLng(item.lat!, item.lng!);
        _mapZoom = 18.0;
      });
      _mainMapController.move(_mapCenter, _mapZoom);
      _snack('Focused map on ${item.controller.text.isEmpty ? "Item" : item.controller.text}');
    } else {
      _snack('Please pin a location for this item first.');
    }
  }

  void _openItemDirections(ChecklistItem item) {
    if (item.lat != null && item.lng != null) {
      final url = 'https://www.google.com/maps/dir/?api=1&destination=${item.lat},${item.lng}';
      if (kIsWeb) {
        html.window.open(url, '_blank');
      }
    } else {
      _snack('Please pin a location first to get directions.');
    }
  }

  void _exportCsvFile() {
    final rawTitle = _titleController.text.trim();
    final title = rawTitle.isEmpty ? 'Itinerary' : rawTitle;
    final csv = ItineraryCodec.toCsvString(title, _days);

    if (kIsWeb) {
      final bytes = utf8.encode(csv);
      final blob = html.Blob([bytes], 'text/csv');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final filename = '${title.toLowerCase().replaceAll(RegExp(r'\s+'), '_')}.csv';

      html.AnchorElement(href: url)
        ..setAttribute("download", filename)
        ..click();

      html.Url.revokeObjectUrl(url);
      _snack('Downloaded $filename successfully');
    }
  }

  Future<void> _importCsvFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );

      if (result != null && result.files.single.bytes != null) {
        final bytes = result.files.single.bytes!;
        final rawContent = utf8.decode(bytes);
        _applyImport(rawContent);
      }
    } catch (e) {
      _snack('Failed to pick file: $e');
    }
  }

  void _applyImport(String raw) {
    try {
      final result = ItineraryCodec.parseCsv(raw);
      final newDays = result.days.isEmpty
          ? <DayEntry>[DayEntry(title: 'Day 1')]
          : result.days;

      final oldDays = List<DayEntry>.of(_days);
      setState(() {
        _titleController.text = result.title;
        _days
          ..clear()
          ..addAll(newDays);

        // Find first item with location to center map
        for (final d in newDays) {
          for (final i in d.items) {
            if (i.lat != null && i.lng != null) {
              _mapCenter = LatLng(i.lat!, i.lng!);
              _mainMapController.move(_mapCenter, 10.0);
              break;
            }
          }
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final d in oldDays) {
          d.dispose();
        }
      });
      _snack('Itinerary imported successfully from CSV file');
    } catch (_) {
      _snack('Import failed: invalid itinerary CSV file format');
    }
  }

  Future<void> _openItemLocationPicker(ChecklistItem item) async {
    LatLng initialCenter = (item.lat != null && item.lng != null)
        ? LatLng(item.lat!, item.lng!)
        : _mapCenter;

    LatLng? selectedPoint = (item.lat != null && item.lng != null) ? initialCenter : null;
    final MapController mapController = MapController();
    final TextEditingController searchController = TextEditingController();
    List<Map<String, dynamic>> searchResults = [];
    bool isSearching = false;

    Future<void> searchLocation(String query, StateSetter setDialogState) async {
      if (query.trim().isEmpty) return;
      setDialogState(() => isSearching = true);
      try {
        final url = Uri.parse(
            'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=5');
        final response = await http.get(url, headers: {'User-Agent': 'FlutterItineraryApp'});
        if (response.statusCode == 200) {
          final List data = jsonDecode(response.body);
          setDialogState(() {
            searchResults = data.cast<Map<String, dynamic>>();
          });
        }
      } catch (_) {}
      setDialogState(() => isSearching = false);
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.coral,
          title: Text('Pin Location for "${item.controller.text.isEmpty ? "Item" : item.controller.text}"', style: TextStyle(color: AppColors.ink)),
          contentPadding: const EdgeInsets.all(2),
          content: WireFrame(
            width: AppResponsive.isDesktop(context) ? context.screenWidth * 0.4 : context.screenWidth,
            height: AppResponsive.isDesktop(context) ? context.screenHeight * 0.5 : context.screenHeight * 0.8,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: searchController,
                        style: TextStyle(color: AppColors.ink),
                        decoration: InputDecoration(
                          hintText: 'Search place (e.g., Tokyo Tower)…',
                          hintStyle: TextStyle(color: AppColors.ink.withOpacity(0.4)),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (val) => searchLocation(val, setDialogState),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: isSearching ? null : () => searchLocation(searchController.text, setDialogState),
                      child: isSearching
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text('Search', style: TextStyle(color: AppColors.ink)),
                    ),
                  ],
                ),
                if (searchResults.isNotEmpty)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 130),
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(4),
                      color: Colors.white,
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: searchResults.length,
                      itemBuilder: (context, index) {
                        final place = searchResults[index];
                        final displayName = place['display_name'] ?? '';
                        return ListTile(
                          dense: true,
                          title: Text(displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.ink)),
                          onTap: () {
                            final lat = double.parse(place['lat']);
                            final lon = double.parse(place['lon']);
                            final point = LatLng(lat, lon);

                            setDialogState(() {
                              selectedPoint = point;
                              item.locationController.text = displayName;
                              searchResults.clear();
                            });

                            mapController.move(point, 14.0);
                          },
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: FlutterMap(
                      mapController: mapController,
                      options: MapOptions(
                        initialCenter: initialCenter,
                        initialZoom: 12,
                        onTap: (tapPosition, point) {
                          setDialogState(() {
                            selectedPoint = point;
                          });
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.example.app',
                        ),
                        if (selectedPoint != null)
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: selectedPoint!,
                                width: 40,
                                height: 40,
                                child: const Icon(Icons.location_pin, color: Colors.red, size: 40),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: item.locationController,
                  style: TextStyle(color: AppColors.ink),
                  decoration: InputDecoration(
                    labelText: 'Location Name / Label',
                    labelStyle: TextStyle(color: AppColors.ink),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: AppColors.ink)),
            ),
            FilledButton(
              onPressed: () {
                if (selectedPoint != null) {
                  setState(() {
                    item.lat = selectedPoint!.latitude;
                    item.lng = selectedPoint!.longitude;
                    item.locationName = item.locationController.text;
                  });
                }
                Navigator.pop(ctx);
              },
              child: Text('Save & Pin', style: TextStyle(color: AppColors.ink)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final buttonStyle = OutlinedButton.styleFrom(
      foregroundColor: _p.card,
      side: BorderSide(color: _p.ink, width: 2),
    );

    // Gather all parent items with locations for map markers
    final markers = <Marker>[];
    for (final d in _days) {
      for (final item in d.items) {
        if (item.indent == 0 && item.lat != null && item.lng != null) {
          markers.add(
            Marker(
              point: LatLng(item.lat!, item.lng!),
              width: 40,
              height: 40,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    d.isMinimized = false;
                  });
                },
                child: Tooltip(
                  message: item.locationName.isNotEmpty ? item.locationName : item.controller.text,
                  child: const Icon(Icons.location_pin, color: Colors.red, size: 40),
                ),
              ),
            ),
          );
        }
      }
    }

    final ref = context.screenWidth;
    final isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    return Theme(
      data: _theme,
      child: Scaffold(
        floatingActionButton: isKeyboardVisible
            ? null
            : Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FloatingActionButton(
                    onPressed: _addDay,
                    child: Icon(Icons.add),
                  ),
                  SizedBox(width: 12,),
                  FloatingActionButton(
                  child: Icon(_showOptions ? Icons.close : Icons.menu),
                  onPressed: () {
                    setState(() {
                      _showOptions = !_showOptions;
                    });
                  },
                ),
                ],
              ),
        body: Stack(
        children: [
          SizedBox(
          height: context.screenHeight,
          child: SingleChildScrollView(
          child: Center(
            child: Padding(
              padding: AppResponsive.isDesktop(context)
                  ? EdgeInsets.fromLTRB(ref * 0.1, 12, ref * 0.1, 96)
                  : const EdgeInsets.fromLTRB(8, 8, 8, 96),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Text(
                    'Build your Itinerary',
                    style: TextStyle(
                      color: _p.ink,
                      fontSize: AppResponsive.titleSize(context),
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.5,
                    ),
                  ),

                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: _titleController,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _p.ink,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Name your trip…  e.g. Tokyo 2027',
                          hintStyle: TextStyle(color: _p.ink.withOpacity(0.4)),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ),

                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        style: buttonStyle,
                        onPressed: _exportCsvFile,
                        icon: const Icon(Icons.download, size: 18),
                        label: const Text('Export CSV File'),
                      ),
                      OutlinedButton.icon(
                        style: buttonStyle,
                        onPressed: _importCsvFile,
                        icon: const Icon(Icons.upload_file, size: 18),
                        label: const Text('Import CSV File'),
                      ),
                      OutlinedButton.icon(
                        style: buttonStyle,
                        onPressed: () => setState(() => _showMap = !_showMap),
                        icon: Icon(_showMap ? Icons.map_outlined : Icons.map, size: 18),
                        label: Text(_showMap ? 'Hide Map' : 'Show Map'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  if (_showMap)
                    Center(
                      child: WireFrame(
                        height: context.screenHeight * 0.4,
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: FlutterMap(
                            mapController: _mainMapController,
                            options: MapOptions(
                              initialCenter: _mapCenter,
                              initialZoom: _mapZoom,
                            ),
                            children: [
                              TileLayer(
                                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.example.app',
                              ),
                              MarkerLayer(markers: markers),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _days.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final day = _days[i];
                      
                      if (day.isMinimized) {
                        return InkWell(
                          onTap: () => setState(() => day.isMinimized = false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: _p.paper,
                              border: Border.all(color: Colors.red.shade400, width: 2),
                              borderRadius: BorderRadius.circular(30),
                              boxShadow: [
                                BoxShadow(color: _p.shadow, offset: const Offset(2, 2)),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.location_pin, color: Colors.red, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  day.titleController.text.isEmpty ? 'Day ${i + 1}' : day.titleController.text,
                                  style: TextStyle(fontWeight: FontWeight.bold, color: _p.ink),
                                ),
                                const Spacer(),
                                Icon(Icons.unfold_more, size: 18, color: _p.ink),
                              ],
                            ),
                          ),
                        );
                      }

                      return _DayCard(
                        key: ObjectKey(day),
                        day: day,
                        onDelete: () => _removeDay(day),
                        onMinimize: () => setState(() => day.isMinimized = true),
                        onPickItemLocation: (item) => _openItemLocationPicker(item),
                        onShowOnMap: (item) => _focusMapOnItem(item),
                        onGetDirections: (item) => _openItemDirections(item),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      if (_showOptions)
        Positioned(
          bottom: 80,
          right: 20,
          child: WireFrame(
            width: 220,
            color: _p.card,
            padding: const EdgeInsets.all(12),
            border: _border,
            boxShadow: _hardShadow(4),
            borderRadius: BorderRadius.circular(12),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _menuItem(
                    icon: Icons.emoji_events,
                    label: 'Home',
                    route: '/',
                  ),
                    _menuItem(
                    icon: Icons.api_outlined,
                    label: 'Tournament',
                    route: '/tournament',
                  ),
                  _menuItem(
                    icon: Icons.fire_extinguisher,
                    label: 'HeatMaps',
                    route: '/heatmap',
                  ),
                  _menuItem(
                    icon: Icons.map_outlined,
                    label: 'Playground',
                    route: '/apiplayground',
                  ),
                  // _menuItem(
                  //   icon: Icons.map_outlined,
                  //   label: 'Grocery list builder',
                  //   route: '/grocery',
                  // ),
                ],
              ),
            ),
          ),
        ),
        ]
        )  
      )
    );
  }
}

// ─────────────────────────── Day card ───────────────────────────

class _DayCard extends StatefulWidget {
  const _DayCard({
    super.key,
    required this.day,
    required this.onDelete,
    required this.onMinimize,
    required this.onPickItemLocation,
    required this.onShowOnMap,
    required this.onGetDirections,
  });

  final DayEntry day;
  final VoidCallback onDelete;
  final VoidCallback onMinimize;
  final ValueChanged<ChecklistItem> onPickItemLocation;
  final ValueChanged<ChecklistItem> onShowOnMap;
  final ValueChanged<ChecklistItem> onGetDirections;

  @override
  State<_DayCard> createState() => _DayCardState();
}

class _DayCardState extends State<_DayCard> {
  DayEntry get day => widget.day;

  @override
  void initState() {
    super.initState();
    for (final item in day.items) {
      _wire(item);
    }
  }

  void _wire(ChecklistItem item) {
    item.focus.onKeyEvent = (node, event) => _onKey(item, event);
    item.focus.addListener(() {
      if (mounted) setState(() {});
    });
  }

  KeyEventResult _onKey(ChecklistItem item, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.tab) {
      final shift = HardwareKeyboard.instance.isShiftPressed;
      _changeIndent(item, shift ? -1 : 1);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        item.controller.text.isEmpty) {
      if (item.indent > 0) {
        _changeIndent(item, -1);
      } else {
        _remove(item);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _changeIndent(ChecklistItem item, int delta) {
    final index = day.items.indexOf(item);
    if (index < 0) return;
    final maxAllowed =
        index == 0 ? 0 : (day.items[index - 1].indent + 1).clamp(0, _maxIndent);
    setState(() {
      item.indent = (item.indent + delta).clamp(0, maxAllowed);
      for (var i = index + 1; i < day.items.length; i++) {
        final limit = day.items[i - 1].indent + 1;
        if (day.items[i].indent > limit) day.items[i].indent = limit;
      }
    });
  }

  void _addAfter(int index) {
    final item = ChecklistItem(indent: 0);
    _wire(item);
    setState(() => day.items.insert(index + 1, item));
    WidgetsBinding.instance
        .addPostFrameCallback((_) => item.focus.requestFocus());
  }

  void _remove(ChecklistItem item) {
    if (day.items.length <= 1) return;
    final index = day.items.indexOf(item);
    setState(() => day.items.removeAt(index));
    final prev = day.items[(index - 1).clamp(0, day.items.length - 1)];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      prev.focus.requestFocus();
      prev.controller.selection =
          TextSelection.collapsed(offset: prev.controller.text.length);
      item.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = theme.extension<AppPalette>()!;
    final shellWidth = math.min(context.screenWidth * 0.95, 1300.0);

    final line = p.ink;
    const margin = Color(0x66C0392B);

    const serif =
        TextStyle(fontFamily: 'Georgia', fontFamilyFallback: ['serif']);
    final textStyle = serif.copyWith(fontSize: 16, color: p.ink, height: 1.4);

    return WireFrame(
      width: shellWidth,
      color: p.paper,
      padding: const EdgeInsets.all(12),
      border: Border.all(color: p.ink, width: 2),
      boxShadow: BoxShadow(
        color: p.shadow,
        offset: const Offset(4, 4),
        blurRadius: 0,
      ),
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          Positioned(
            left: 6,
            top: 0,
            bottom: 0,
            child: Container(width: 1.5, color: const Color.fromARGB(102, 245, 24, 0)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: day.titleController,
                        style: textStyle.copyWith(
                            fontSize: 22, fontWeight: FontWeight.bold),
                        decoration: const InputDecoration(
                          hintText: 'Day title / date',
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Minimize to Bubble',
                      icon: Icon(Icons.unfold_less, color: p.ink.withOpacity(0.5)),
                      onPressed: widget.onMinimize,
                    ),
                    IconButton(
                      tooltip: 'Delete day',
                      icon: Icon(Icons.delete_outline,
                          color: p.ink.withOpacity(0.5)),
                      onPressed: widget.onDelete,
                    ),
                  ],
                ),
                Divider(color: line, height: 8),

                for (var i = 0; i < day.items.length; i++)
                  _buildItem(day.items[i], i, textStyle, line, p.ink),

                TextButton.icon(
                  onPressed: () => _addAfter(day.items.length - 1),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text('Add item', style: TextStyle(color: p.ink)),
                ),

                const SizedBox(height: 4),
                Text('Notes',
                    style: textStyle.copyWith(
                        fontSize: 13, color: p.ink.withOpacity(0.55))),
                TextField(
                  controller: day.notesController,
                  style: textStyle,
                  minLines: 2,
                  maxLines: null,
                  decoration: InputDecoration(
                    hintText: 'Write anything about this day…',
                    hintStyle: textStyle.copyWith(color: p.ink.withOpacity(0.35)),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(ChecklistItem item, int index, TextStyle style, Color line, Color ink) {
    final isParent = item.indent == 0;

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: line)),
      ),
      padding: EdgeInsets.only(left: item.indent * 26.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 32,
                height: 36,
                child: Checkbox(
                  value: item.done,
                  visualDensity: VisualDensity.compact,
                  shape: isParent ? null : const CircleBorder(),
                  onChanged: (v) => setState(() => item.done = v ?? false),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: item.controller,
                  focusNode: item.focus,
                  textInputAction: TextInputAction.newline,
                  minLines: 1,
                  maxLines: null,
                  onSubmitted: (_) => _addAfter(index),
                  style: style.copyWith(
                    fontSize: isParent ? 16 : 15,
                    decoration: item.done
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                    color: item.done ? ink.withOpacity(0.45) : ink,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                    hintText: 'Plan something…',
                  ),
                ),
              ),
              _MiniButton(
                icon: Icons.format_indent_decrease,
                color: ink.withOpacity(0.6),
                onTap: () {
                  _changeIndent(item, -1);
                  item.focus.requestFocus();
                },
                tooltip: 'Decrease Indent',
              ),
              _MiniButton(
                icon: Icons.format_indent_increase,
                color: ink.withOpacity(0.6),
                onTap: () {
                  _changeIndent(item, 1);
                  item.focus.requestFocus();
                },
                tooltip: 'Increase Indent',
              ),
            ],
          ),
          if (isParent)
            Padding(
              padding: const EdgeInsets.only(left: 32, bottom: 6),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  if (item.lat != null && item.lng != null) ...[
                    ActionChip(
                      avatar: const Icon(Icons.map, size: 16, color: Colors.blue),
                      label: const Text('Show on Map', style: TextStyle(fontSize: 12)),
                      onPressed: () => widget.onShowOnMap(item),
                      visualDensity: VisualDensity.compact,
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.directions, size: 16, color: Colors.green),
                      label: const Text('Directions', style: TextStyle(fontSize: 12)),
                      onPressed: () => widget.onGetDirections(item),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                  ActionChip(
                    avatar: Icon(Icons.location_pin, size: 16, color: item.lat != null ? Colors.red : ink.withOpacity(0.5)),
                    label: Text(item.lat != null ? 'Pinned' : 'Pin Location', style: TextStyle(fontSize: 12)),
                    onPressed: () => widget.onPickItemLocation(item),
                    visualDensity: VisualDensity.compact,
                  ),
                  if (item.locationName.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 4),
                      child: Text(
                        '📍 ${item.locationName}',
                        style: TextStyle(fontSize: 12, color: Colors.red.shade700, fontWeight: FontWeight.w500),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({required this.icon, required this.onTap, this.color, this.tooltip});

  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    Widget child = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 18, color: color),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: child);
    }
    return child;
  }
}