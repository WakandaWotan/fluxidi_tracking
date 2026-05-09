import 'package:flutter/material.dart';

enum _TransferMode { toAirport, fromAirport }

class AirportPage extends StatefulWidget {
  const AirportPage({super.key});

  @override
  State<AirportPage> createState() => _AirportPageState();
}

class _AirportPageState extends State<AirportPage> {
  static const Color _bg = Color(0xFF07080C);
  static const Color _panel = Color(0xFF101010);
  static const Color _gold = Color(0xFFE5B641);
  static const Color _soft = Color(0xFFB4B4B4);

  static const List<String> _airports = <String>[
    'Brussels Airport',
    'Charleroi Airport',
    'Amsterdam Schiphol',
    'Paris Charles de Gaulle',
    'London Heathrow',
  ];

  _TransferMode _selectedMode = _TransferMode.toAirport;
  String _selectedAirport = _airports.first;
  int _passengers = 1;
  int _bags = 0;
  bool _meetAndGreet = false;

  final TextEditingController _pickupAddressController =
      TextEditingController();
  final TextEditingController _destinationAddressController =
      TextEditingController();
  final TextEditingController _pickupDateTimeController =
      TextEditingController();
  final TextEditingController _landingDateTimeController =
      TextEditingController();
  final TextEditingController _flightNumberController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _nameBoardController = TextEditingController();

  @override
  void dispose() {
    _pickupAddressController.dispose();
    _destinationAddressController.dispose();
    _pickupDateTimeController.dispose();
    _landingDateTimeController.dispose();
    _flightNumberController.dispose();
    _noteController.dispose();
    _nameBoardController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = width < 360 ? 12.0 : 14.0;
    final stackedActions = width < 385;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  8,
                  horizontalPadding,
                  16,
                ),
                children: [
                  _buildHero(),
                  const SizedBox(height: 10),
                  _buildDirectionActions(stacked: stackedActions),
                  const SizedBox(height: 10),
                  _buildIntakePanel(),
                  const SizedBox(height: 12),
                  _buildCtaButton(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
            color: _gold,
            tooltip: 'Terug',
          ),
          const SizedBox(width: 2),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Luchthavenvervoer',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Premium transfers voor comfortabele ritten van en naar de luchthaven',
                  style: TextStyle(color: _soft, fontSize: 11.5, height: 1.2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _gold.withOpacity(0.28)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF12110A), Color(0xFF07080C)],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _gold.withOpacity(0.45)),
              color: _gold.withOpacity(0.14),
            ),
            child: const Icon(Icons.local_taxi_rounded, color: _gold, size: 30),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Zakelijk en privé luchthavenvervoer',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Plan binnenkort direct uw transfer met heldere serviceopties en betrouwbare chauffeurs.',
                  style: TextStyle(color: _soft, fontSize: 11.8, height: 1.25),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectionActions({required bool stacked}) {
    final first = _actionCard(
      title: 'Naar de luchthaven',
      subtitle: 'Vertrek op tijd met comfortabele ophaalservice.',
      icon: Icons.flight_takeoff_rounded,
      mode: _TransferMode.toAirport,
    );
    final second = _actionCard(
      title: 'Van de luchthaven',
      subtitle: 'Aankomsttransfer met duidelijke afhaalafspraken.',
      icon: Icons.flight_land_rounded,
      mode: _TransferMode.fromAirport,
    );
    if (stacked) {
      return Column(children: [first, const SizedBox(height: 8), second]);
    }
    return Row(
      children: [
        Expanded(child: first),
        const SizedBox(width: 8),
        Expanded(child: second),
      ],
    );
  }

  Widget _actionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required _TransferMode mode,
  }) {
    final isSelected = _selectedMode == mode;
    return Container(
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected ? _gold : _gold.withOpacity(0.26),
          width: isSelected ? 1.6 : 1,
        ),
        boxShadow: isSelected
            ? <BoxShadow>[
                BoxShadow(
                  color: _gold.withOpacity(0.28),
                  blurRadius: 14,
                  spreadRadius: 0.2,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              _selectedMode = mode;
            });
          },
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? _gold.withOpacity(0.22)
                        : _gold.withOpacity(0.14),
                    border: Border.all(
                      color: isSelected
                          ? _gold.withOpacity(0.72)
                          : _gold.withOpacity(0.4),
                    ),
                  ),
                  child: Icon(icon, color: _gold, size: 18),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isSelected ? _gold : Colors.white,
                          fontSize: 12.8,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _soft,
                          fontSize: 11,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _gold.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: _gold.withOpacity(0.7)),
                    ),
                    child: const Text(
                      'Actief',
                      style: TextStyle(
                        color: _gold,
                        fontSize: 10.6,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    String? subtitle,
    Widget? child,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _gold.withOpacity(0.96), size: 17),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(
                color: _soft,
                fontSize: 11.7,
                height: 1.25,
              ),
            ),
          ],
          if (child != null) ...[const SizedBox(height: 8), child],
        ],
      ),
    );
  }

  Widget _buildIntakePanel() {
    final isToAirport = _selectedMode == _TransferMode.toAirport;
    return _sectionCard(
      title: isToAirport
          ? 'Intake: naar de luchthaven'
          : 'Intake: van de luchthaven',
      icon: isToAirport
          ? Icons.directions_car_filled_rounded
          : Icons.local_taxi_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isToAirport) ...[
            _buildTextField(
              label: 'Ophaaladres',
              controller: _pickupAddressController,
              hint: 'Straat, nummer, postcode, stad',
              icon: Icons.pin_drop_outlined,
            ),
            const SizedBox(height: 10),
            _buildAirportDropdown(),
            const SizedBox(height: 10),
            _buildTextField(
              label: 'Ophaaldatum en tijd',
              controller: _pickupDateTimeController,
              hint: 'Bijv. 21/06/2026 - 05:45',
              icon: Icons.schedule_rounded,
            ),
            const SizedBox(height: 10),
            _buildStepperRow(
              label: 'Passagiers',
              value: _passengers,
              min: 1,
              max: 8,
              icon: Icons.groups_2_outlined,
              onChanged: (value) => setState(() => _passengers = value),
            ),
            const SizedBox(height: 10),
            _buildStepperRow(
              label: 'Bagage',
              value: _bags,
              min: 0,
              max: 12,
              icon: Icons.luggage_outlined,
              onChanged: (value) => setState(() => _bags = value),
            ),
            const SizedBox(height: 10),
            _buildTextField(
              label: 'Opmerking (optioneel)',
              controller: _noteController,
              hint: 'Extra info voor de chauffeur',
              icon: Icons.edit_note_rounded,
              minLines: 2,
              maxLines: 3,
            ),
            const SizedBox(height: 10),
            Text(
              'Prijsberekening en boeking worden in een volgende stap gekoppeld.',
              style: TextStyle(
                color: _soft.withOpacity(0.95),
                fontSize: 11.4,
                height: 1.25,
              ),
            ),
          ] else ...[
            _buildAirportDropdown(),
            const SizedBox(height: 10),
            _buildTextField(
              label: 'Bestemmingsadres',
              controller: _destinationAddressController,
              hint: 'Straat, nummer, postcode, stad',
              icon: Icons.location_on_outlined,
            ),
            const SizedBox(height: 10),
            _buildTextField(
              label: 'Vluchtnummer (optioneel)',
              controller: _flightNumberController,
              hint: 'Bijv. SN204',
              icon: Icons.confirmation_number_outlined,
            ),
            const SizedBox(height: 10),
            _buildTextField(
              label: 'Landingsdatum en tijd',
              controller: _landingDateTimeController,
              hint: 'Bijv. 21/06/2026 - 18:20',
              icon: Icons.schedule_rounded,
            ),
            const SizedBox(height: 10),
            _buildMeetAndGreetToggle(),
            if (_meetAndGreet) ...[
              const SizedBox(height: 10),
              _buildTextField(
                label: 'Naam op bordje',
                controller: _nameBoardController,
                hint: 'Bijv. Mevr. Van Dijk',
                icon: Icons.badge_outlined,
              ),
            ],
            const SizedBox(height: 10),
            _buildStepperRow(
              label: 'Passagiers',
              value: _passengers,
              min: 1,
              max: 8,
              icon: Icons.groups_2_outlined,
              onChanged: (value) => setState(() => _passengers = value),
            ),
            const SizedBox(height: 10),
            _buildStepperRow(
              label: 'Bagage',
              value: _bags,
              min: 0,
              max: 12,
              icon: Icons.luggage_outlined,
              onChanged: (value) => setState(() => _bags = value),
            ),
            const SizedBox(height: 10),
            Text(
              'Vluchttracking en boeking worden in een volgende stap gekoppeld.',
              style: TextStyle(
                color: _soft.withOpacity(0.95),
                fontSize: 11.4,
                height: 1.25,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAirportDropdown() {
    return InputDecorator(
      decoration: _fieldDecoration(
        label: 'Luchthaven',
        prefixIcon: Icons.flight_rounded,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedAirport,
          isDense: true,
          isExpanded: true,
          dropdownColor: const Color(0xFF1A1A1A),
          iconEnabledColor: _gold,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          items: _airports
              .map(
                (airport) => DropdownMenuItem<String>(
                  value: airport,
                  child: Text(airport),
                ),
              )
              .toList(growable: false),
          onChanged: (value) {
            if (value == null) {
              return;
            }
            setState(() {
              _selectedAirport = value;
            });
          },
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    int maxLines = 1,
    int minLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      minLines: minLines,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: _fieldDecoration(
        label: label,
        hintText: hint,
        prefixIcon: icon,
      ),
    );
  }

  Widget _buildStepperRow({
    required String label,
    required int value,
    required int min,
    required int max,
    required IconData icon,
    required ValueChanged<int> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _gold.withOpacity(0.32)),
      ),
      child: Row(
        children: [
          Icon(icon, color: _gold, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _stepButton(
            icon: Icons.remove_rounded,
            enabled: value > min,
            onTap: () => onChanged(value - 1),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              '$value',
              style: const TextStyle(
                color: _gold,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          _stepButton(
            icon: Icons.add_rounded,
            enabled: value < max,
            onTap: () => onChanged(value + 1),
          ),
        ],
      ),
    );
  }

  Widget _stepButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: enabled ? _gold.withOpacity(0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: enabled ? _gold.withOpacity(0.72) : _soft.withOpacity(0.3),
            ),
          ),
          child: Icon(
            icon,
            size: 16,
            color: enabled ? _gold : _soft.withOpacity(0.55),
          ),
        ),
      ),
    );
  }

  Widget _buildMeetAndGreetToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _meetAndGreet
              ? _gold.withOpacity(0.7)
              : _gold.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.support_agent_rounded,
            color: _meetAndGreet ? _gold : _soft,
            size: 18,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Meet & greet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12.8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Switch(
            value: _meetAndGreet,
            activeColor: _gold,
            inactiveThumbColor: _soft,
            inactiveTrackColor: const Color(0xFF2E2E2E),
            onChanged: (value) {
              setState(() {
                _meetAndGreet = value;
                if (!value) {
                  _nameBoardController.clear();
                }
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCtaButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: _gold,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 14),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Deze flow koppelt in de volgende fase met prijsberekening en boeking.',
              ),
            ),
          );
        },
        child: const Text('Ritgegevens voorbereiden'),
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    String? hintText,
    required IconData prefixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      labelStyle: TextStyle(color: _soft.withOpacity(0.95), fontSize: 12.2),
      hintStyle: TextStyle(color: _soft.withOpacity(0.55), fontSize: 12),
      prefixIcon: Icon(prefixIcon, color: _gold.withOpacity(0.92), size: 18),
      filled: true,
      fillColor: const Color(0xFF181818),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _gold.withOpacity(0.32)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _gold, width: 1.2),
      ),
    );
  }
}
