import 'package:flutter/material.dart';
import '../business_theme_palette.dart';

class CompanyDriverCodePickerEntry {
  const CompanyDriverCodePickerEntry({
    required this.name,
    required this.status,
    required this.onSelected,
  });
  final String name;
  final String status;
  final VoidCallback onSelected;
}

Color driverCodePickerInk(Color requested, Color surface) {
  final a = requested.computeLuminance(), b = surface.computeLuminance();
  final ratio = ((a > b ? a : b) + .05) / ((a > b ? b : a) + .05);
  if (ratio >= 4.5) return requested;
  return (b + .05) / .05 >= 1.05 / (b + .05) ? Colors.black : Colors.white;
}

class CompanyDriverCodePickerSheet extends StatelessWidget {
  const CompanyDriverCodePickerSheet({
    super.key,
    required this.palette,
    required this.title,
    required this.entries,
  });
  final BusinessThemePalette palette;
  final String title;
  final List<CompanyDriverCodePickerEntry> entries;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(
            color: driverCodePickerInk(palette.textPrimary, palette.surface), fontWeight: FontWeight.w800,
          )),
          const SizedBox(height: 8),
          for (final entry in entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(entry.name, style: TextStyle(color: driverCodePickerInk(palette.textPrimary, palette.surface))),
              subtitle: Text(entry.status, style: TextStyle(color: driverCodePickerInk(palette.textSecondary, palette.surface))),
              trailing: Icon(Icons.chevron_right, color: driverCodePickerInk(palette.textSecondary, palette.surface)),
              onTap: entry.onSelected,
            ),
        ],
      ),
    ),
  );
}
