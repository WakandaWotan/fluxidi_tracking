import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/driver_document_sheet.dart';
import 'package:fluxidi_tracking/driver_documents_store.dart';
import 'package:image_picker/image_picker.dart';

class VehicleManagementPage extends StatefulWidget {
  const VehicleManagementPage({super.key});

  @override
  State<VehicleManagementPage> createState() => _VehicleManagementPageState();
}

class _VehicleManagementPageState extends State<VehicleManagementPage> {
  final ImagePicker _imagePicker = ImagePicker();
  static const int _maxPhotosPerVehicle = 5;
  AppLanguage get _lang => appConfig.currentLanguage;

  @override
  void initState() {
    super.initState();
    DriverDocumentsStore.instance.load();
  }

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) {
    switch (_lang) {
      case AppLanguage.nl:
        return nl;
      case AppLanguage.en:
        return en;
      case AppLanguage.fr:
        return fr;
      case AppLanguage.es:
        return es;
    }
  }

  String _tierLabel(String tierId) {
    for (final t in appConfig.enabledTiers) {
      if (t.id == tierId) return t.labelFor(_lang);
    }
    return tierId;
  }

  Future<void> _syncFleetOrShowError() async {
    final ok = await syncFleetInventoryToBackend();
    if (ok || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            nl: 'Voertuigen lokaal opgeslagen, maar backend-sync mislukt. Controleer ADMIN_TOKEN/netwerk en probeer opnieuw.',
            en: 'Vehicles were saved locally, but backend sync failed. Check ADMIN_TOKEN/network and try again.',
            fr: 'Vehicules sauvegardes localement, mais la synchronisation backend a echoue. Verifiez ADMIN_TOKEN/reseau et reessayez.',
            es: 'Vehiculos guardados localmente, pero fallo la sincronizacion backend. Verifica ADMIN_TOKEN/red e intentalo de nuevo.',
          ),
        ),
      ),
    );
  }

  bool _isAssetRef(String value) =>
      value.trim().toLowerCase().startsWith('assets/');

  /// Vehicle row scoped to current local tenant when present; preserves stored id on edit.
  String? _scopedVehicleCompanyId(VehicleProfile? existing) {
    if (existing != null) {
      final t = existing.companyId?.trim();
      if (t != null && t.isNotEmpty) return t;
    }
    return companyProfileNotifier.value != null ? resolvedCompanyId : null;
  }

  DriverProfile? _driverById(String? driverId) {
    if (driverId == null || driverId.trim().isEmpty) return null;
    for (final d in driversNotifier.value) {
      if (d.id == driverId) return d;
    }
    return null;
  }

  Future<bool> _confirmVehicleUpsellIfNeeded() async {
    final currentCount = vehiclesNotifier.value.length;
    if (currentCount < includedVehicleLimit) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _t(
            nl: 'Extra voertuig',
            en: 'Additional vehicle',
            fr: 'Vehicule supplementaire',
            es: 'Vehiculo adicional',
          ),
        ),
        content: Text(
          _t(
            nl: 'Je abonnement bevat 1 voertuig. Extra voertuigen vallen onder een upsell van €${fleetSubscriptionPolicy.additionalVehicleMonthlyPrice.toStringAsFixed(0)} per voertuig per maand.',
            en: 'Your subscription includes 1 vehicle. Additional vehicles use an upsell of €${fleetSubscriptionPolicy.additionalVehicleMonthlyPrice.toStringAsFixed(0)} per vehicle per month.',
            fr: 'Votre abonnement inclut 1 vehicule. Les vehicules supplementaires utilisent un supplement de €${fleetSubscriptionPolicy.additionalVehicleMonthlyPrice.toStringAsFixed(0)} par vehicule et par mois.',
            es: 'Tu suscripcion incluye 1 vehiculo. Los vehiculos adicionales aplican un cargo de €${fleetSubscriptionPolicy.additionalVehicleMonthlyPrice.toStringAsFixed(0)} por vehiculo al mes.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              _t(nl: 'Annuleren', en: 'Cancel', fr: 'Annuler', es: 'Cancelar'),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              _t(
                nl: 'Doorgaan',
                en: 'Continue',
                fr: 'Continuer',
                es: 'Continuar',
              ),
            ),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<DriverProfile?> _openDriverCreator() async {
    final nameCtrl = TextEditingController();
    final idCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final taxiCardNumberCtrl = TextEditingController();
    final taxiCardExpiryCtrl = TextEditingController();
    DriverProfile? created;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141B2F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          _t(
            nl: 'Chauffeur toevoegen',
            en: 'New driver',
            fr: 'Ajouter un chauffeur',
            es: 'Agregar conductor',
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _txt(nameCtrl, _t(nl: 'Naam', en: 'Name', fr: 'Nom', es: 'Nombre')),
            _txt(
              idCtrl,
              _t(
                nl: 'Chauffeur-ID',
                en: 'Driver ID',
                fr: 'ID chauffeur',
                es: 'ID conductor',
              ),
            ),
            _txt(
              phoneCtrl,
              _t(
                nl: 'Telefoonnummer',
                en: 'Phone number',
                fr: 'Numero de telephone',
                es: 'Numero de telefono',
              ),
            ),
            _txt(
              taxiCardNumberCtrl,
              _t(
                nl: 'Chauffeurskaartnummer',
                en: 'Taxi driver card number',
                fr: 'Numero de carte chauffeur',
                es: 'Numero de tarjeta de conductor',
              ),
            ),
            _txt(
              taxiCardExpiryCtrl,
              _t(
                nl: 'Vervaldatum chauffeurskaart',
                en: 'Taxi driver card expiry',
                fr: 'Expiration carte chauffeur',
                es: 'Vencimiento tarjeta de conductor',
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 12,
                      ),
                    ),
                    child: Text(
                      _t(
                        nl: 'Annuleren',
                        en: 'Cancel',
                        fr: 'Annuler',
                        es: 'Cancelar',
                      ),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      final fullName = nameCtrl.text.trim();
                      final employeeNumber = idCtrl.text.trim();
                      if (fullName.isEmpty || employeeNumber.isEmpty) return;
                      created = DriverProfile(
                        id: 'drv_${DateTime.now().millisecondsSinceEpoch}',
                        fullName: fullName,
                        employeeNumber: employeeNumber,
                        phone: phoneCtrl.text.trim(),
                        taxiDriverCardNumber: taxiCardNumberCtrl.text.trim(),
                        taxiDriverCardExpiry: taxiCardExpiryCtrl.text.trim(),
                        isActive: true,
                        companyId: companyProfileNotifier.value != null
                            ? resolvedCompanyId
                            : null,
                      );
                      addDriver(created!);
                      Navigator.pop(ctx);
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 12,
                      ),
                    ),
                    child: Text(
                      _t(
                        nl: 'Toevoegen',
                        en: 'Add',
                        fr: 'Ajouter',
                        es: 'Agregar',
                      ),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    return created;
  }

  Future<void> _pickVehiclePhoto({
    required String currentRef,
    required void Function(String ref) onPicked,
  }) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      if (picked == null) return;
      onPicked(picked.path);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Kon geen foto selecteren.',
              en: 'Could not select photo.',
              fr: 'Impossible de selectionner la photo.',
              es: 'No se pudo seleccionar la foto.',
            ),
          ),
        ),
      );
      onPicked(currentRef);
    }
  }

  Future<List<String>> _pickVehiclePhotos() async {
    try {
      final picked = await _imagePicker.pickMultiImage(imageQuality: 90);
      if (picked.isEmpty) return const <String>[];
      return picked
          .map((x) => x.path)
          .where((p) => p.trim().isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      if (!mounted) return const <String>[];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Kon geen foto\'s selecteren.',
              en: 'Could not select photos.',
              fr: 'Impossible de selectionner les photos.',
              es: 'No se pudieron seleccionar las fotos.',
            ),
          ),
        ),
      );
      return const <String>[];
    }
  }

  Widget _photoPreviewBox({
    required String photoRef,
    required double height,
    required VoidCallback? onTap,
    required String placeholderText,
  }) {
    final clean = photoRef.trim();
    final isAsset = _isAssetRef(clean);
    final hasRef = clean.isNotEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        height: height,
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12),
        ),
        child: isAsset
            ? ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Image.asset(
                  clean,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      _photoPlaceholder(placeholderText),
                ),
              )
            : (hasRef
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: kIsWeb
                          ? Image.network(
                              clean,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _photoPlaceholder(placeholderText),
                            )
                          : Image.file(
                              File(clean),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _photoPlaceholder(placeholderText),
                            ),
                    )
                  : _photoPlaceholder(placeholderText)),
      ),
    );
  }

  Widget _photoPlaceholder(String text) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.image_not_supported_outlined, color: Colors.white54),
          const SizedBox(height: 6),
          Text(
            text,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _openVehicleEditor({VehicleProfile? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.vehicleName ?? '');
    final modelCtrl = TextEditingController(text: existing?.brandModel ?? '');
    final plateCtrl = TextEditingController(text: existing?.licensePlate ?? '');
    final exploitationLicenseCtrl = TextEditingController(
      text: existing?.exploitationLicenseNumber ?? '',
    );
    final vehicleRegistrationCtrl = TextEditingController(
      text: existing?.vehicleRegistrationNumber ?? '',
    );
    final colorCtrl = TextEditingController(text: existing?.color ?? '');
    var primaryPhotoRef = existing?.primaryPhotoRef ?? '';
    var galleryPhotoRefs = List<String>.from(
      existing?.galleryPhotoRefs ?? const <String>[],
    );
    final paxCtrl = TextEditingController(
      text: (existing?.passengerCapacity ?? 3).toString(),
    );
    final bagsCtrl = TextEditingController(
      text: (existing?.luggageCapacity ?? 3).toString(),
    );
    var tierId = existing?.tierId ?? appConfig.enabledTiers.first.id;
    String? linkedDriverId = existing?.driverId;
    {
      final cid = _scopedVehicleCompanyId(existing);
      final dr0 = _driverById(linkedDriverId);
      if (dr0 != null && !canAssignDriverToVehicleCompany(dr0, cid)) {
        linkedDriverId = null;
      }
    }
    var active = existing?.isActive ?? true;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141B2F),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 12,
                right: 12,
                top: 12,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 14,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      existing == null
                          ? _t(
                              nl: 'Voertuig toevoegen',
                              en: 'Add vehicle',
                              fr: 'Ajouter vehicule',
                              es: 'Agregar vehiculo',
                            )
                          : _t(
                              nl: 'Voertuig bewerken',
                              en: 'Edit vehicle',
                              fr: 'Modifier vehicule',
                              es: 'Editar vehiculo',
                            ),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _txt(
                      nameCtrl,
                      _t(
                        nl: 'Voertuignaam',
                        en: 'Vehicle name',
                        fr: 'Nom vehicule',
                        es: 'Nombre del vehiculo',
                      ),
                    ),
                    _txt(
                      modelCtrl,
                      _t(
                        nl: 'Merk/model',
                        en: 'Brand/model',
                        fr: 'Marque/modele',
                        es: 'Marca/modelo',
                      ),
                    ),
                    _txt(
                      plateCtrl,
                      _t(
                        nl: 'Nummerplaat',
                        en: 'License plate',
                        fr: 'Plaque',
                        es: 'Matricula',
                      ),
                    ),
                    _txt(
                      exploitationLicenseCtrl,
                      _t(
                        nl: 'Exploitatievergunningnummer',
                        en: 'Exploitation license number',
                        fr: 'Numero de licence d exploitation',
                        es: 'Numero de licencia de explotacion',
                      ),
                    ),
                    _txt(
                      vehicleRegistrationCtrl,
                      _t(
                        nl: 'Chassisnummer',
                        en: 'Vehicle registration/VIN/chassis number',
                        fr: 'Numero d immatriculation/VIN/chassis',
                        es: 'Numero de matricula/VIN/chasis',
                      ),
                    ),
                    _txt(
                      colorCtrl,
                      _t(nl: 'Kleur', en: 'Color', fr: 'Couleur', es: 'Color'),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _txt(
                            paxCtrl,
                            _t(
                              nl: 'Passagierscapaciteit',
                              en: 'Passenger capacity',
                              fr: 'Capacite passagers',
                              es: 'Capacidad pasajeros',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _txt(
                            bagsCtrl,
                            _t(
                              nl: 'Bagagecapaciteit',
                              en: 'Luggage capacity',
                              fr: 'Capacite bagages',
                              es: 'Capacidad equipaje',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: tierId,
                      isExpanded: true,
                      items: appConfig.enabledTiers
                          .map(
                            (t) => DropdownMenuItem(
                              value: t.id,
                              child: Text(t.labelFor(_lang)),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (v) {
                        if (v == null) return;
                        setLocalState(() => tierId = v);
                      },
                      decoration: InputDecoration(
                        labelText: _t(
                          nl: 'Tier/klasse',
                          en: 'Tier/class',
                          fr: 'Categorie',
                          es: 'Categoria',
                        ),
                        filled: true,
                        fillColor: const Color(0xFF0B0B0B),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                      ),
                      dropdownColor: const Color(0xFF111111),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _t(
                                nl: 'Actief',
                                en: 'Active',
                                fr: 'Actif',
                                es: 'Activo',
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Switch(
                            value: active,
                            onChanged: (v) => setLocalState(() => active = v),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _t(
                        nl: 'Gekoppelde chauffeur',
                        en: 'Linked driver',
                        fr: 'Chauffeur lie',
                        es: 'Conductor vinculado',
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: linkedDriverId,
                      isExpanded: true,
                      items: <DropdownMenuItem<String>>[
                        DropdownMenuItem<String>(
                          value: null,
                          child: Text(
                            _t(
                              nl: 'Geen chauffeur',
                              en: 'No driver',
                              fr: 'Aucun chauffeur',
                              es: 'Sin conductor',
                            ),
                          ),
                        ),
                        ...driversNotifier.value
                            .where(
                              (d) =>
                                  fleetRecordBelongsToActiveCompanyOrLegacy(
                                    d.companyId,
                                  ) &&
                                  !fleetExplicitCompanyMismatch(
                                    d.companyId,
                                    _scopedVehicleCompanyId(existing),
                                  ),
                            )
                            .map(
                              (d) => DropdownMenuItem<String>(
                                value: d.id,
                                child: Text(
                                  '${d.fullName} (${d.employeeNumber})',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                      ],
                      onChanged: (v) => setLocalState(() => linkedDriverId = v),
                      decoration: InputDecoration(
                        labelText: _t(
                          nl: 'Selecteer chauffeur',
                          en: 'Select driver',
                          fr: 'Selectionner chauffeur',
                          es: 'Seleccionar conductor',
                        ),
                        filled: true,
                        fillColor: const Color(0xFF0B0B0B),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                      ),
                      dropdownColor: const Color(0xFF111111),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () async {
                        final created = await _openDriverCreator();
                        if (created == null) return;
                        setLocalState(() => linkedDriverId = created.id);
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          const Icon(Icons.person_add_alt_1),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _t(
                                nl: 'Chauffeur toevoegen',
                                en: 'Add new driver',
                                fr: 'Ajouter un chauffeur',
                                es: 'Agregar nuevo conductor',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_driverById(linkedDriverId) != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          border: Border.all(color: const Color(0x33FFD400)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Builder(
                          builder: (context) {
                            final d = _driverById(linkedDriverId)!;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _t(
                                    nl: 'Chauffeurgegevens',
                                    en: 'Driver details',
                                    fr: 'Details du chauffeur',
                                    es: 'Detalles del conductor',
                                  ),
                                  style: const TextStyle(
                                    color: Color(0xFFFFD54F),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _driverInfoLine(
                                  _t(
                                    nl: 'Naam',
                                    en: 'Name',
                                    fr: 'Nom',
                                    es: 'Nombre',
                                  ),
                                  d.fullName,
                                ),
                                const SizedBox(height: 4),
                                _driverInfoLine(
                                  _t(
                                    nl: 'Chauffeur-ID',
                                    en: 'Driver ID',
                                    fr: 'ID chauffeur',
                                    es: 'ID conductor',
                                  ),
                                  d.employeeNumber,
                                ),
                                const SizedBox(height: 4),
                                _driverInfoLine(
                                  _t(
                                    nl: 'Telefoonnummer',
                                    en: 'Phone number',
                                    fr: 'Numero de telephone',
                                    es: 'Numero de telefono',
                                  ),
                                  d.phone,
                                ),
                                const SizedBox(height: 4),
                                _driverInfoLine(
                                  _t(
                                    nl: 'Chauffeurskaartnummer',
                                    en: 'Taxi driver card number',
                                    fr: 'Numero carte chauffeur',
                                    es: 'Numero tarjeta conductor',
                                  ),
                                  d.taxiDriverCardNumber,
                                ),
                                const SizedBox(height: 4),
                                _driverInfoLine(
                                  _t(
                                    nl: 'Vervaldatum chauffeurskaart',
                                    en: 'Taxi driver card expiry',
                                    fr: 'Expiration carte chauffeur',
                                    es: 'Vencimiento tarjeta conductor',
                                  ),
                                  d.taxiDriverCardExpiry,
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _photoPreviewBox(
                      photoRef: primaryPhotoRef,
                      height: 120,
                      onTap: () async {
                        await _pickVehiclePhoto(
                          currentRef: primaryPhotoRef,
                          onPicked: (ref) => setLocalState(() {
                            primaryPhotoRef = ref;
                            if (ref.trim().isNotEmpty &&
                                !galleryPhotoRefs.contains(ref)) {
                              galleryPhotoRefs =
                                  <String>[ref, ...galleryPhotoRefs]
                                      .where((e) => e.trim().isNotEmpty)
                                      .toSet()
                                      .toList(growable: false);
                              if (galleryPhotoRefs.length >
                                  _maxPhotosPerVehicle) {
                                galleryPhotoRefs = galleryPhotoRefs
                                    .take(_maxPhotosPerVehicle)
                                    .toList(growable: false);
                              }
                            }
                          }),
                        );
                      },
                      placeholderText: _t(
                        nl: 'Geen foto ingesteld',
                        en: 'No photo set',
                        fr: 'Aucune photo definie',
                        es: 'Sin foto configurada',
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (galleryPhotoRefs.isNotEmpty) ...[
                      Text(
                        _t(
                          nl: 'Galerijfoto\'s',
                          en: 'Gallery photos',
                          fr: 'Photos galerie',
                          es: 'Fotos de galeria',
                        ),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 82,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: galleryPhotoRefs.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, i) {
                            final ref = galleryPhotoRefs[i];
                            final isMain = ref == primaryPhotoRef;
                            return Stack(
                              children: [
                                Container(
                                  width: 110,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isMain
                                          ? Colors.amberAccent
                                          : Colors.white24,
                                      width: isMain ? 2 : 1,
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(9),
                                    child: _photoPreviewBox(
                                      photoRef: ref,
                                      height: 80,
                                      onTap: () => setLocalState(
                                        () => primaryPhotoRef = ref,
                                      ),
                                      placeholderText: _t(
                                        nl: 'Geen foto',
                                        en: 'No photo',
                                        fr: 'Pas de photo',
                                        es: 'Sin foto',
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: 2,
                                  top: 2,
                                  child: InkWell(
                                    onTap: () => setLocalState(() {
                                      galleryPhotoRefs = List<String>.from(
                                        galleryPhotoRefs,
                                      )..remove(ref);
                                      if (primaryPhotoRef == ref) {
                                        primaryPhotoRef =
                                            galleryPhotoRefs.isNotEmpty
                                            ? galleryPhotoRefs.first
                                            : '';
                                      }
                                    }),
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: const Icon(Icons.close, size: 14),
                                    ),
                                  ),
                                ),
                                if (isMain)
                                  Positioned(
                                    left: 4,
                                    bottom: 4,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        _t(
                                          nl: 'Hoofd',
                                          en: 'Main',
                                          fr: 'Principale',
                                          es: 'Principal',
                                        ),
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed:
                              galleryPhotoRefs.length >= _maxPhotosPerVehicle
                              ? null
                              : () async {
                                  final pickedRefs = await _pickVehiclePhotos();
                                  if (pickedRefs.isEmpty) return;
                                  final freeSlots =
                                      _maxPhotosPerVehicle -
                                      galleryPhotoRefs.length;
                                  final accepted = pickedRefs
                                      .take(freeSlots)
                                      .toList(growable: false);
                                  if (accepted.isEmpty) return;
                                  setLocalState(() {
                                    galleryPhotoRefs =
                                        <String>[
                                              ...galleryPhotoRefs,
                                              ...accepted,
                                            ]
                                            .where((e) => e.trim().isNotEmpty)
                                            .toSet()
                                            .take(_maxPhotosPerVehicle)
                                            .toList(growable: false);
                                    if (primaryPhotoRef.trim().isEmpty &&
                                        galleryPhotoRefs.isNotEmpty) {
                                      primaryPhotoRef = galleryPhotoRefs.first;
                                    }
                                  });
                                  if (pickedRefs.length > accepted.length &&
                                      mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          _t(
                                            nl: 'Niet alle foto\'s toegevoegd (maximaal 5).',
                                            en: 'Not all photos added (maximum 5).',
                                            fr: 'Toutes les photos n\'ont pas ete ajoutees (maximum 5).',
                                            es: 'No se agregaron todas las fotos (maximo 5).',
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                },
                          icon: const Icon(Icons.upload_file),
                          label: Text(
                            _t(
                              nl: 'Foto\'s toevoegen',
                              en: 'Add photos',
                              fr: 'Ajouter des photos',
                              es: 'Agregar fotos',
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: primaryPhotoRef.trim().isEmpty
                              ? null
                              : () => _pickVehiclePhoto(
                                  currentRef: primaryPhotoRef,
                                  onPicked: (ref) => setLocalState(() {
                                    if (ref.trim().isEmpty) return;
                                    primaryPhotoRef = ref;
                                    if (!galleryPhotoRefs.contains(ref)) {
                                      galleryPhotoRefs =
                                          <String>[ref, ...galleryPhotoRefs]
                                              .where((e) => e.trim().isNotEmpty)
                                              .toSet()
                                              .toList(growable: false);
                                      if (galleryPhotoRefs.length >
                                          _maxPhotosPerVehicle) {
                                        galleryPhotoRefs = galleryPhotoRefs
                                            .take(_maxPhotosPerVehicle)
                                            .toList(growable: false);
                                      }
                                    }
                                  }),
                                ),
                          icon: const Icon(Icons.edit_outlined),
                          label: Text(
                            _t(
                              nl: 'Hoofdfoto wijzigen',
                              en: 'Change main photo',
                              fr: 'Changer photo principale',
                              es: 'Cambiar foto principal',
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => setLocalState(() {
                            primaryPhotoRef = '';
                            galleryPhotoRefs = <String>[];
                          }),
                          icon: const Icon(Icons.delete_outline),
                          label: Text(
                            _t(
                              nl: 'Alle foto\'s verwijderen',
                              en: 'Remove all photos',
                              fr: 'Supprimer toutes les photos',
                              es: 'Eliminar todas las fotos',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _t(
                        nl: 'Maximaal 5 foto\'s per voertuig',
                        en: 'Maximum 5 photos per vehicle',
                        fr: 'Maximum 5 photos par vehicule',
                        es: 'Maximo 5 fotos por vehiculo',
                      ),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                            ),
                            child: Text(
                              _t(
                                nl: 'Annuleren',
                                en: 'Cancel',
                                fr: 'Annuler',
                                es: 'Cancelar',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: () async {
                              final cid = _scopedVehicleCompanyId(existing);
                              if (linkedDriverId != null) {
                                final dr = _driverById(linkedDriverId);
                                if (dr != null &&
                                    !canAssignDriverToVehicleCompany(dr, cid)) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        _t(
                                          nl: 'Deze chauffeur hoort niet bij dit bedrijf.',
                                          en: 'This driver does not belong to this company.',
                                          fr: 'Ce chauffeur n appartient pas a cette entreprise.',
                                          es: 'Este conductor no pertenece a esta empresa.',
                                        ),
                                      ),
                                    ),
                                  );
                                  return;
                                }
                              }
                              final vehicle = VehicleProfile(
                                id:
                                    existing?.id ??
                                    'vh_${DateTime.now().millisecondsSinceEpoch}',
                                vehicleName: nameCtrl.text.trim(),
                                brandModel: modelCtrl.text.trim(),
                                licensePlate: plateCtrl.text.trim(),
                                exploitationLicenseNumber:
                                    exploitationLicenseCtrl.text.trim(),
                                vehicleRegistrationNumber:
                                    vehicleRegistrationCtrl.text.trim(),
                                color: colorCtrl.text.trim(),
                                passengerCapacity:
                                    int.tryParse(paxCtrl.text.trim()) ?? 0,
                                luggageCapacity:
                                    int.tryParse(bagsCtrl.text.trim()) ?? 0,
                                tierId: tierId,
                                isActive: active,
                                driverId: linkedDriverId,
                                companyId: cid,
                                primaryPhotoRef: primaryPhotoRef.trim(),
                                galleryPhotoRefs: galleryPhotoRefs
                                    .where((e) => e.trim().isNotEmpty)
                                    .take(_maxPhotosPerVehicle)
                                    .toList(growable: false),
                              );
                              if (existing == null) {
                                addVehicle(vehicle);
                              } else {
                                updateVehicle(existing.id, vehicle);
                              }
                              await _syncFleetOrShowError();
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                            },
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                            ),
                            child: Text(
                              _t(
                                nl: 'Opslaan',
                                en: 'Save',
                                fr: 'Enregistrer',
                                es: 'Guardar',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _txt(
    TextEditingController ctrl,
    String label, {
    VoidCallback? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: ctrl,
        onChanged: onChanged == null ? null : (_) => onChanged(),
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          filled: true,
          fillColor: const Color(0xFF0B0B0B),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0x22FFFFFF)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0x22FFFFFF)),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteDocument(DriverDocument doc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141B2F),
        title: Text(
          _t(
            nl: 'Document verwijderen?',
            en: 'Delete document?',
            fr: 'Supprimer le document?',
            es: 'Eliminar documento?',
          ),
        ),
        content: Text(
          doc.title.trim().isEmpty ? doc.documentId : doc.title.trim(),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              _t(nl: 'Annuleren', en: 'Cancel', fr: 'Annuler', es: 'Cancelar'),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              _t(
                nl: 'Verwijderen',
                en: 'Delete',
                fr: 'Supprimer',
                es: 'Eliminar',
              ),
            ),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await DriverDocumentsStore.instance.deleteDocument(doc.documentId);
    }
  }

  Future<void> _openDocumentEditor(
    DriverProfile driver, {
    DriverDocument? existing,
  }) => showDriverDocumentEditorSheet(
    context,
    driver: driver,
    existing: existing,
  );

  Widget _buildDriversDocumentsBlock() {
    return ValueListenableBuilder<List<DriverDocument>>(
      valueListenable: driverDocumentsNotifier,
      builder: (context, _, __) {
        return ValueListenableBuilder<List<DriverProfile>>(
          valueListenable: driversNotifier,
          builder: (context, drivers, _) {
            final filtered = drivers
                .where(
                  (d) => fleetRecordBelongsToActiveCompanyOrLegacy(d.companyId),
                )
                .toList(growable: false);
            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t(
                      nl: 'Documenten',
                      en: 'Documents',
                      fr: 'Documents',
                      es: 'Documentos',
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _t(
                      nl: 'Lokale documentopslag voor test/MVP. In productie moeten gevoelige documenten veilig en versleuteld worden opgeslagen met passend toegangsbeheer.',
                      en: 'Local document storage for test/MVP. In production, sensitive documents must be stored on a secure encrypted backend with appropriate access control.',
                      fr: 'Stockage local pour test/MVP. En production, les documents sensibles doivent etre stockes sur un backend securise et chiffre avec un controle d acces adapte.',
                      es: 'Almacenamiento local para prueba/MVP. En produccion, los documentos sensibles deben almacenarse en un backend seguro y cifrado con control de acceso adecuado.',
                    ),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.62),
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (filtered.isEmpty)
                    Text(
                      _t(
                        nl: 'Geen chauffeurs.',
                        en: 'No drivers.',
                        fr: 'Aucun chauffeur.',
                        es: 'Sin conductores.',
                      ),
                      style: const TextStyle(color: Colors.white54),
                    )
                  else
                    ...filtered.map(_driverDocumentsExpansion),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _driverDocumentsExpansion(DriverProfile driver) {
    final docs = DriverDocumentsStore.instance.documentsVisibleForDriver(
      driver.id,
    );
    final count = docs.length;
    final gap = DriverDocumentsStore.instance.hasCoreDocumentGapForDriver(
      driver.id,
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: const Color(0xFF141B2F),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Colors.white12),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        title: Text(
          driver.fullName.isEmpty
              ? _t(
                  nl: 'Naamloze chauffeur',
                  en: 'Unnamed driver',
                  fr: 'Chauffeur sans nom',
                  es: 'Conductor sin nombre',
                )
              : driver.fullName,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        subtitle: Text(
          '$count ${_t(nl: 'documenten', en: 'documents', fr: 'documents', es: 'documentos')}'
          '${gap ? ' • ${_t(nl: 'Controleer kern-documenten', en: 'Check core documents', fr: 'Verifier documents', es: 'Revise documentos')}' : ''}',
          style: TextStyle(
            color: gap ? Colors.orangeAccent : Colors.white54,
            fontSize: 12,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (docs.isEmpty)
                  Text(
                    _t(
                      nl: 'Nog geen documenten.',
                      en: 'No documents yet.',
                      fr: 'Aucun document.',
                      es: 'Sin documentos.',
                    ),
                    style: const TextStyle(color: Colors.white54),
                  )
                else
                  ...docs.map(_driverDocumentTile),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _openDocumentEditor(driver),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(
                    _t(
                      nl: 'Document toevoegen',
                      en: 'Add document',
                      fr: 'Ajouter',
                      es: 'Agregar',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _driverDocumentTile(DriverDocument doc) {
    final typeLabel = driverDocumentTypeLabel(doc.documentType, _lang);
    final expiredVisual =
        doc.isExpiredByDate || doc.status == DriverDocumentStatuses.expired;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: expiredVisual
              ? Colors.orange.withOpacity(0.6)
              : Colors.white24,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            typeLabel,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (doc.title.trim().isNotEmpty)
            Text(
              doc.title,
              style: const TextStyle(fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 4),
          Text(
            '${_t(nl: 'Status', en: 'Status', fr: 'Statut', es: 'Estado')}: ${driverDocumentStatusLabel(doc.status, _lang)}'
            '${doc.isExpiredByDate && doc.status != DriverDocumentStatuses.expired ? ' (${_t(nl: 'datum verlopen', en: 'date expired', fr: 'date expiree', es: 'fecha caducada')})' : ''}',
            style: TextStyle(
              color: expiredVisual ? Colors.orangeAccent : Colors.white70,
              fontSize: 12,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          if (doc.expiryDate.trim().isNotEmpty)
            Text(
              '${_t(nl: 'Vervaldatum', en: 'Expiry', fr: 'Expiration', es: 'Caducidad')}: ${doc.expiryDate}',
              style: const TextStyle(fontSize: 11, color: Colors.white54),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          if (doc.filePath.trim().isNotEmpty) ...[
            Text(
              '${_t(nl: 'Bestand', en: 'File', fr: 'Fichier', es: 'Archivo')}',
              style: const TextStyle(fontSize: 11, color: Colors.white54),
            ),
            driverDocAttachmentPreview(doc.filePath, _lang),
            SizedBox(
              width: double.infinity,
              child: Text(
                doc.filePath,
                style: const TextStyle(fontSize: 10, color: Colors.white38),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          if (doc.notes.trim().isNotEmpty)
            Text(
              '${_t(nl: 'Notities', en: 'Notes', fr: 'Notes', es: 'Notas')}: ${doc.notes}',
              style: const TextStyle(fontSize: 11, color: Colors.white60),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            alignment: WrapAlignment.start,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: doc.filePath.trim().isEmpty
                    ? null
                    : () =>
                          openDriverDocumentFile(context, doc.filePath, _lang),
                child: Text(
                  _t(nl: 'Openen', en: 'Open', fr: 'Ouvrir', es: 'Abrir'),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () {
                  DriverProfile? dr;
                  for (final x in driversNotifier.value) {
                    if (x.id == doc.driverId) {
                      dr = x;
                      break;
                    }
                  }
                  if (dr == null) return;
                  _openDocumentEditor(dr, existing: doc);
                },
                child: Text(
                  _t(nl: 'Bewerken', en: 'Edit', fr: 'Modifier', es: 'Editar'),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => _confirmDeleteDocument(doc),
                child: Text(
                  _t(
                    nl: 'Verwijderen',
                    en: 'Delete',
                    fr: 'Supprimer',
                    es: 'Eliminar',
                  ),
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _driverInfoLine(String label, String value) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(color: Colors.white),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(
            text: value.isEmpty ? '—' : value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => Scaffold(
        backgroundColor: const Color(0xFF0B1020),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0B1020),
          title: Text(
            _t(
              nl: 'Voertuigen',
              en: 'Vehicles',
              fr: 'Vehicules',
              es: 'Vehiculos',
            ),
          ),
          actions: [
            IconButton(
              tooltip: _t(
                nl: 'Voertuig toevoegen',
                en: 'Add vehicle',
                fr: 'Ajouter vehicule',
                es: 'Agregar vehiculo',
              ),
              onPressed: () async {
                if (!await _confirmVehicleUpsellIfNeeded()) return;
                await _openVehicleEditor();
              },
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        body: ValueListenableBuilder<List<VehicleProfile>>(
          valueListenable: vehiclesNotifier,
          builder: (context, vehicles, _) {
            final visible = vehicles
                .where(
                  (v) => fleetRecordBelongsToActiveCompanyOrLegacy(v.companyId),
                )
                .toList(growable: false);
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildDriversDocumentsBlock()),
                if (visible.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _t(
                            nl: 'Nog geen voertuigen.',
                            en: 'No vehicles yet.',
                            fr: 'Aucun vehicule.',
                            es: 'Sin vehiculos.',
                          ),
                          style: const TextStyle(color: Colors.white70),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, i) {
                        final v = visible[i];
                        final linkedDriver = _driverById(v.driverId);
                        final status = v.isActive
                            ? _t(
                                nl: 'Actief',
                                en: 'Active',
                                fr: 'Actif',
                                es: 'Activo',
                              )
                            : _t(
                                nl: 'Inactief',
                                en: 'Inactive',
                                fr: 'Inactif',
                                es: 'Inactivo',
                              );
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF141B2F),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      v.vehicleName.isEmpty
                                          ? _t(
                                              nl: 'Naamloos voertuig',
                                              en: 'Unnamed vehicle',
                                              fr: 'Vehicule sans nom',
                                              es: 'Vehiculo sin nombre',
                                            )
                                          : v.vehicleName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    status,
                                    style: TextStyle(
                                      color: v.isActive
                                          ? Colors.greenAccent
                                          : Colors.white54,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${_t(nl: 'Bedrijf (lokaal)', en: 'Company (local)', fr: 'Entreprise (locale)', es: 'Empresa (local)')}: '
                                '${(v.companyId?.trim().isNotEmpty ?? false) ? v.companyId!.trim() : _t(nl: '(legacy)', en: '(legacy)', fr: '(ancien)', es: '(legacy)')}',
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                              Text(
                                '${_t(nl: 'Merk/model', en: 'Brand/model', fr: 'Marque/modele', es: 'Marca/modelo')}: ${v.brandModel.isEmpty ? '—' : v.brandModel}',
                              ),
                              Text(
                                '${_t(nl: 'Nummerplaat', en: 'License plate', fr: 'Plaque', es: 'Matricula')}: ${v.licensePlate.isEmpty ? '—' : v.licensePlate}',
                              ),
                              Text(
                                '${_t(nl: 'Exploitatievergunningnummer', en: 'Exploitation license number', fr: 'Numero licence exploitation', es: 'Numero licencia explotacion')}: ${v.exploitationLicenseNumber.isEmpty ? '—' : v.exploitationLicenseNumber}',
                              ),
                              Text(
                                '${_t(nl: 'Chassisnummer', en: 'Vehicle registration/VIN/chassis number', fr: 'Immatriculation/VIN/chassis', es: 'Matricula/VIN/chasis')}: ${v.vehicleRegistrationNumber.isEmpty ? '—' : v.vehicleRegistrationNumber}',
                              ),
                              Text(
                                '${_t(nl: 'Kleur', en: 'Color', fr: 'Couleur', es: 'Color')}: ${v.color.isEmpty ? '—' : v.color}',
                              ),
                              Text(
                                '${_t(nl: 'Capaciteit', en: 'Capacity', fr: 'Capacite', es: 'Capacidad')}: ${v.passengerCapacity} pax • ${v.luggageCapacity} bags',
                              ),
                              Text(
                                '${_t(nl: 'Tier/klasse', en: 'Tier/class', fr: 'Categorie', es: 'Categoria')}: ${_tierLabel(v.tierId)}',
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_t(nl: 'Gekoppelde chauffeur', en: 'Linked driver', fr: 'Chauffeur lie', es: 'Conductor vinculado')}: '
                                '${linkedDriver == null ? '—' : linkedDriver.fullName}',
                              ),
                              if (linkedDriver != null) ...[
                                Text(
                                  '${_t(nl: 'Chauffeur-ID', en: 'Driver ID', fr: 'ID chauffeur', es: 'ID conductor')}: ${linkedDriver.employeeNumber}',
                                ),
                                Text(
                                  '${_t(nl: 'Telefoon', en: 'Phone', fr: 'Telephone', es: 'Telefono')}: ${linkedDriver.phone.isEmpty ? '—' : linkedDriver.phone}',
                                ),
                                Text(
                                  '${_t(nl: 'Chauffeurskaartnummer', en: 'Taxi driver card number', fr: 'Numero carte chauffeur', es: 'Numero tarjeta conductor')}: ${linkedDriver.taxiDriverCardNumber.isEmpty ? '—' : linkedDriver.taxiDriverCardNumber}',
                                ),
                                Text(
                                  '${_t(nl: 'Vervaldatum chauffeurskaart', en: 'Taxi driver card expiry', fr: 'Expiration carte chauffeur', es: 'Vencimiento tarjeta conductor')}: ${linkedDriver.taxiDriverCardExpiry.isEmpty ? '—' : linkedDriver.taxiDriverCardExpiry}',
                                ),
                              ],
                              const SizedBox(height: 6),
                              _photoPreviewBox(
                                photoRef: v.primaryPhotoRef,
                                height: 140,
                                onTap: null,
                                placeholderText: _t(
                                  nl: 'Geen foto ingesteld',
                                  en: 'No photo set',
                                  fr: 'Aucune photo definie',
                                  es: 'Sin foto configurada',
                                ),
                              ),
                              if (v.galleryPhotoRefs.length > 1) ...[
                                const SizedBox(height: 6),
                                Text(
                                  _t(
                                    nl: '+${v.galleryPhotoRefs.length - 1} extra foto\'s',
                                    en: '+${v.galleryPhotoRefs.length - 1} extra photos',
                                    fr: '+${v.galleryPhotoRefs.length - 1} photos en plus',
                                    es: '+${v.galleryPhotoRefs.length - 1} fotos extra',
                                  ),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () =>
                                          _openVehicleEditor(existing: v),
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 16,
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 10,
                                        ),
                                      ),
                                      label: Text(
                                        _t(
                                          nl: 'Bewerken',
                                          en: 'Edit',
                                          fr: 'Modifier',
                                          es: 'Editar',
                                        ),
                                        maxLines: 1,
                                        softWrap: false,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () async {
                                        deleteVehicle(v.id);
                                        await _syncFleetOrShowError();
                                      },
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        size: 16,
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 10,
                                        ),
                                      ),
                                      label: Text(
                                        _t(
                                          nl: 'Verwijder',
                                          en: 'Delete',
                                          fr: 'Supprimer',
                                          es: 'Eliminar',
                                        ),
                                        maxLines: 1,
                                        softWrap: false,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }, childCount: visible.length),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
