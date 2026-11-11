import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/geofence_plan.dart';
import '../../geofence/location_access.dart';
import '../../models/task_location.dart';
import '../../providers/geofence_providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// Opens the full-screen map and answers the chosen place, or null when the
/// user backed out without choosing (`design/task-editor-spec.md` §7).
Future<TaskLocation?> pickLocation(
  BuildContext context, {
  TaskLocation? initial,
}) => Navigator.of(context).push<TaskLocation>(
  MaterialPageRoute<TaskLocation>(
    fullscreenDialog: true,
    builder: (_) => LocationPickerScreen(initial: initial),
  ),
);

/// The OpenStreetMap tiles, under the OSM tile usage policy
/// (https://operations.osmfoundation.org/policies/tiles/):
///
/// - a User-Agent that identifies the app (`userAgentPackageName`, which
///   flutter_map turns into `flutter_map (com.taskradar.app)`), never the
///   library default;
/// - the attribution «© участники OpenStreetMap» always visible on the map and
///   linking to the copyright page;
/// - no prefetching or bulk download: tiles are fetched only as the user pans,
///   and flutter_map's built-in cache honours the server's cache headers;
/// - zoom capped at 19, the highest level the standard layer serves.
const String osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const String osmUserAgentPackage = 'com.taskradar.app';
const String osmCopyrightUrl = 'https://www.openstreetmap.org/copyright';

/// Where the map opens when there is neither a saved place nor a known
/// position: the middle of Moscow, zoomed out to the city.
const LatLng _fallbackCenter = LatLng(55.7558, 37.6173);
const double _fallbackZoom = 10;
const double _placeZoom = 16;

/// The map screen. The pin stays in the middle and the map moves under it:
/// drag the map, or tap a point to bring it under the pin. «Моё место» centres
/// on the current position; the slider sets the radius (100–1000 m, step 50)
/// and the circle shows it; the label is optional and saves as «Место».
class LocationPickerScreen extends ConsumerStatefulWidget {
  const LocationPickerScreen({
    super.key,
    this.initial,
    @visibleForTesting this.tileProvider,
  });

  final TaskLocation? initial;

  /// Tests replace the network with blank tiles.
  final TileProvider? tileProvider;

  @override
  ConsumerState<LocationPickerScreen> createState() =>
      _LocationPickerScreenState();
}

class _LocationPickerScreenState extends ConsumerState<LocationPickerScreen> {
  final MapController _map = MapController();
  late final TextEditingController _label = TextEditingController(
    text: widget.initial?.label == defaultPlaceLabel
        ? ''
        : widget.initial?.label ?? '',
  );

  late LatLng _center = widget.initial == null
      ? _fallbackCenter
      : LatLng(widget.initial!.lat, widget.initial!.lng);
  late int _radius = (widget.initial?.radius ?? TaskLocation.defaultRadius)
      .clamp(TaskLocation.minRadius, TaskLocation.maxRadius);

  bool _mapReady = false;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    // A new place starts where the phone is, if the OS already knows that
    // without a prompt -- the most likely place is "here".
    if (widget.initial == null) _centreOnLastKnown();
  }

  @override
  void dispose() {
    _label.dispose();
    _map.dispose();
    super.dispose();
  }

  Future<void> _centreOnLastKnown() async {
    final access = ref.read(locationAccessProvider);
    if (!(await access.check()).canLocate) return;
    final point = await access.lastKnownPosition();
    if (point == null || !mounted) return;
    _moveTo(LatLng(point.lat, point.lng), _placeZoom);
  }

  /// A move asked for before the map was laid out (the last known position
  /// can arrive first); applied in `onMapReady`.
  double? _pendingZoom;

  void _moveTo(LatLng point, [double? zoom]) {
    setState(() => _center = point);
    if (_mapReady) {
      _map.move(point, zoom ?? _map.camera.zoom);
    } else {
      _pendingZoom = zoom ?? _pendingZoom;
    }
  }

  void _onMapReady() {
    _mapReady = true;
    final zoom = _pendingZoom;
    if (zoom != null) {
      _pendingZoom = null;
      _map.move(_center, zoom);
    }
  }

  Future<void> _locate() async {
    if (_locating) return;
    final access = ref.read(locationAccessProvider);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _locating = true);
    try {
      var level = await access.check();
      if (level == LocationAccessLevel.denied) level = await access.request();

      if (!level.canLocate) {
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              level == LocationAccessLevel.unsupported
                  ? 'Геопозиция здесь недоступна — выберите место на карте.'
                  : 'Нет доступа к геопозиции. Место можно выбрать на карте '
                        'или разрешить доступ в настройках телефона.',
            ),
            action: level == LocationAccessLevel.deniedForever
                ? SnackBarAction(
                    label: 'Настройки',
                    onPressed: access.openAppSettings,
                  )
                : null,
          ),
        );
        return;
      }

      final point = await access.currentPosition();
      if (!mounted) return;
      if (point == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Не удалось определить, где вы. Проверьте, что геолокация '
              'включена, или выберите место на карте.',
            ),
          ),
        );
        return;
      }
      _moveTo(LatLng(point.lat, point.lng), _placeZoom);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _done() {
    final label = _label.text.trim();
    Navigator.of(context).pop(
      TaskLocation(
        lat: _round(_center.latitude),
        lng: _round(_center.longitude),
        radius: _radius,
        label: label.isEmpty ? defaultPlaceLabel : label,
      ),
    );
  }

  /// Six decimals is ~10 cm: more digits are noise from the map's float maths
  /// and only make the stored value look more precise than a finger is.
  static double _round(double value) =>
      (value * 1000000).roundToDouble() / 1000000;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.voiceBackground,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _Header(onDone: _done),
              Expanded(child: _buildMap()),
              _Controls(
                radius: _radius,
                label: _label,
                onRadius: (value) => setState(() => _radius = value),
                onDone: _done,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMap() {
    return Stack(
      children: <Widget>[
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: _center,
            initialZoom: widget.initial == null ? _fallbackZoom : _placeZoom,
            minZoom: 3,
            maxZoom: 19,
            backgroundColor: AppColors.voiceWell,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            onMapReady: _onMapReady,
            onTap: (_, point) => _moveTo(point),
            onPositionChanged: (camera, hasGesture) {
              if (hasGesture) setState(() => _center = camera.center);
            },
          ),
          children: <Widget>[
            TileLayer(
              urlTemplate: osmTileUrl,
              userAgentPackageName: osmUserAgentPackage,
              maxNativeZoom: 19,
              tileProvider: widget.tileProvider,
            ),
            CircleLayer(
              circles: <CircleMarker>[
                CircleMarker(
                  point: _center,
                  radius: _radius.toDouble(),
                  useRadiusInMeter: true,
                  color: AppColors.voiceLevelHigh.withValues(alpha: 0.18),
                  borderColor: AppColors.voiceLevelHigh,
                  borderStrokeWidth: 2,
                ),
              ],
            ),
            RichAttributionWidget(
              alignment: AttributionAlignment.bottomLeft,
              showFlutterMapAttribution: false,
              attributions: <SourceAttribution>[
                TextSourceAttribution(
                  '© участники OpenStreetMap',
                  onTap: () => launchUrl(
                    Uri.parse(osmCopyrightUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              ],
            ),
          ],
        ),
        // The pin: its tip is the chosen point, i.e. the map's centre.
        const IgnorePointer(
          child: Align(
            child: Padding(
              padding: EdgeInsets.only(bottom: 40),
              child: Icon(
                Icons.location_on,
                key: ValueKey<String>('location-picker-pin'),
                size: 44,
                color: AppColors.voiceRecording,
                shadows: <Shadow>[Shadow(blurRadius: 6)],
              ),
            ),
          ),
        ),
        Positioned(
          right: 12,
          bottom: 12,
          child: FloatingActionButton.extended(
            heroTag: null,
            onPressed: _locating ? null : _locate,
            backgroundColor: AppColors.voiceWell,
            foregroundColor: AppColors.voiceInk,
            icon: _locating
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.voiceInk,
                    ),
                  )
                : const Icon(Icons.my_location),
            label: const Text('Моё место'),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: 'Закрыть',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close),
            color: AppColors.voiceInk,
          ),
          Expanded(
            child: Text(
              'Место',
              style: AppText.screenTight.copyWith(color: AppColors.voiceInk),
            ),
          ),
          TextButton(
            onPressed: onDone,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.voiceBright,
            ),
            child: const Text('Готово'),
          ),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.radius,
    required this.label,
    required this.onRadius,
    required this.onDone,
  });

  final int radius;
  final TextEditingController label;
  final ValueChanged<int> onRadius;
  final VoidCallback onDone;

  static const int _step = 50;

  @override
  Widget build(BuildContext context) {
    final muted = AppText.hint.copyWith(color: AppColors.voiceMuted);
    return Container(
      color: AppColors.voiceBackground,
      padding: const EdgeInsets.fromLTRB(Insets.gutter, 12, Insets.gutter, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('Радиус', style: muted),
              const Spacer(),
              Text(
                '$radius м',
                key: const ValueKey<String>('location-picker-radius'),
                style: AppText.action.copyWith(color: AppColors.voiceInk),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.voiceLevelHigh,
              inactiveTrackColor: AppColors.voiceLine,
              thumbColor: AppColors.voiceBright,
              overlayColor: AppColors.voiceLevelHigh.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: radius.toDouble(),
              min: TaskLocation.minRadius.toDouble(),
              max: TaskLocation.maxRadius.toDouble(),
              divisions:
                  (TaskLocation.maxRadius - TaskLocation.minRadius) ~/ _step,
              label: '$radius м',
              semanticFormatterCallback: (value) => '${value.round()} метров',
              onChanged: (value) => onRadius(value.round()),
            ),
          ),
          Text(
            'Меньше 100 м телефон замечает ненадёжно; для магазина хватит '
            '150–300 м.',
            style: muted,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: label,
            maxLength: 80,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onDone(),
            style: AppText.body.copyWith(color: AppColors.voiceInk),
            cursorColor: AppColors.voiceBright,
            decoration: InputDecoration(
              labelText: 'Подпись',
              hintText: defaultPlaceLabel,
              labelStyle: muted,
              hintStyle: muted,
              counterStyle: muted,
              filled: true,
              fillColor: AppColors.voiceWell,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Radii.chip),
                borderSide: const BorderSide(color: AppColors.voiceLine),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Radii.chip),
                borderSide: const BorderSide(
                  color: AppColors.voiceLevelHigh,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
