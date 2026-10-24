import 'package:flutter/material.dart';

/// Paints before platform storage/session restoration. Never exposes a session
/// or dashboard until the existing initialization and lock gates are ready.
class AppStartupShell extends StatefulWidget {
  const AppStartupShell({
    super.key,
    required this.initialize,
    required this.builder,
    this.name = 'FLUXIDI',
  });
  final Future<void> Function() initialize;
  final WidgetBuilder builder;
  final String name;
  @override
  State<AppStartupShell> createState() => _AppStartupShellState();
}

class _AppStartupShellState extends State<AppStartupShell> {
  late Future<void> _ready;
  @override
  void initState() {
    super.initState();
    _ready = Future<void>.delayed(Duration.zero, widget.initialize);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _ready,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.done &&
          !snapshot.hasError)
        return widget.builder(context);
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF111820),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.name,
                  style: const TextStyle(
                    color: Color(0xFFE5B641),
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 24),
                if (!snapshot.hasError)
                  const CircularProgressIndicator(color: Color(0xFFE5B641))
                else
                  FilledButton(
                    onPressed: () => setState(() {
                      _ready = widget.initialize();
                    }),
                    child: const Text('Opnieuw proberen'),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
