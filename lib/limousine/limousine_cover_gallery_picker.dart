// Visual picker for an existing published limousine photo. Does not mutate
// the vehicle gallery. Dedupes on durable media identity.

import 'package:flutter/material.dart';

import '../app_config.dart';
import '../app_strings.dart';
import '../vehicle_gallery_contract.dart';
import 'limousine_business_setup.dart';
import 'limousine_business_setup_labels.dart';
import 'limousine_p2d4c1a_ux.dart';

class LimousineCoverGalleryItem {
  const LimousineCoverGalleryItem({
    required this.url,
    required this.mediaId,
    required this.vehicleId,
    required this.vehicleName,
    required this.photoIndex,
  });

  final String url;
  final String mediaId;
  final String vehicleId;
  final String vehicleName;
  final int photoIndex;
}

List<String> limousineCoverGalleryCandidateUrls(VehicleProfile vehicle) {
  return <String>[
    if ((vehicle.publicPhotoUrl ?? '').startsWith('https://'))
      vehicle.publicPhotoUrl!,
    if (vehicle.primaryPhotoRef.startsWith('https://')) vehicle.primaryPhotoRef,
    for (final ref in vehicle.galleryPhotoRefs)
      if (ref.startsWith('https://')) ref,
  ];
}

List<LimousineCoverGalleryItem> limousineCoverGalleryItems(
  Iterable<VehicleProfile> vehicles,
) {
  final items = <LimousineCoverGalleryItem>[];
  final seen = <String>{};
  for (final vehicle in limousineSetupLimousineVehicles(vehicles)) {
    final name = vehicle.vehicleName.trim().isEmpty
        ? vehicle.brandModel
        : vehicle.vehicleName;
    var index = 0;
    for (final url in limousineCoverGalleryCandidateUrls(vehicle)) {
      final mediaId = publicMediaObjectIdentity(url);
      if (mediaId.isEmpty || !seen.add(mediaId)) continue;
      index += 1;
      items.add(
        LimousineCoverGalleryItem(
          url: url,
          mediaId: mediaId,
          vehicleId: vehicle.id,
          vehicleName: name,
          photoIndex: index,
        ),
      );
    }
  }
  return items;
}

Future<LimousineCoverGalleryItem?> showLimousineCoverGalleryPicker({
  required BuildContext context,
  required List<LimousineCoverGalleryItem> items,
  required LimousineUxTokens tokens,
  required AppLanguage language,
  String selectedUrl = '',
}) {
  if (items.isEmpty) return Future<LimousineCoverGalleryItem?>.value();
  return showDialog<LimousineCoverGalleryItem>(
    context: context,
    builder: (dialogContext) {
      return _LimousineCoverGalleryDialog(
        items: items,
        tokens: tokens,
        language: language,
        selectedUrl: selectedUrl,
      );
    },
  );
}

class _LimousineCoverGalleryDialog extends StatefulWidget {
  const _LimousineCoverGalleryDialog({
    required this.items,
    required this.tokens,
    required this.language,
    required this.selectedUrl,
  });

  final List<LimousineCoverGalleryItem> items;
  final LimousineUxTokens tokens;
  final AppLanguage language;
  final String selectedUrl;

  @override
  State<_LimousineCoverGalleryDialog> createState() =>
      _LimousineCoverGalleryDialogState();
}

class _LimousineCoverGalleryDialogState
    extends State<_LimousineCoverGalleryDialog> {
  late String _selectedId;

  @override
  void initState() {
    super.initState();
    final current = publicMediaObjectIdentity(widget.selectedUrl);
    _selectedId = widget.items.any((item) => item.mediaId == current)
        ? current
        : widget.items.first.mediaId;
  }

  String _t(LocalizedText text) => text.of(widget.language);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final tablet = size.shortestSide >= 600;
    final columns = tablet ? 3 : 2;
    final selected = widget.items.firstWhere(
      (item) => item.mediaId == _selectedId,
      orElse: () => widget.items.first,
    );
    return AlertDialog(
      key: kLimousineBusinessSetupCoverGalleryDialogKey,
      backgroundColor: widget.tokens.surface,
      title: Text(_t(kLimousineBusinessSetupCoverPickGallery)),
      content: SizedBox(
        width: tablet ? 640 : 360,
        height: tablet ? 420 : 360,
        child: GridView.builder(
          itemCount: widget.items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: tablet ? 0.92 : 0.84,
          ),
          itemBuilder: (context, index) {
            final item = widget.items[index];
            final isSelected = item.mediaId == _selectedId;
            return InkWell(
              key: limousineBusinessSetupCoverGalleryItemKey(item.mediaId),
              onTap: () => setState(() => _selectedId = item.mediaId),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? widget.tokens.gold
                        : widget.tokens.border,
                    width: isSelected ? 3 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(10),
                        ),
                        child: Image.network(
                          item.url,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => ColoredBox(
                            color: widget.tokens.surfaceAlt,
                            child: Icon(
                              Icons.directions_car_filled_outlined,
                              color: widget.tokens.gold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.vehicleName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: widget.tokens.onSurface,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                          Text(
                            limousineBusinessSetupCoverGalleryPhotoLabel(
                              item.photoIndex,
                              widget.language,
                            ),
                            style: TextStyle(
                              color: widget.tokens.muted,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          key: kLimousineBusinessSetupCoverGalleryCancelKey,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_t(kLimousineBusinessSetupLeaveCancel)),
        ),
        FilledButton(
          key: kLimousineBusinessSetupCoverGalleryUseKey,
          onPressed: () => Navigator.of(context).pop(selected),
          child: Text(_t(kLimousineBusinessSetupCoverGalleryUse)),
        ),
      ],
    );
  }
}
