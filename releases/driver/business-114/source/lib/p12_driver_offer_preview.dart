import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/driver/driver_ride_offer.dart';
import 'package:fluxidi_tracking/driver/driver_ride_offer_panel.dart';
// Offline R&D entrypoint; no API, booking, payment, driver identity or GPS.
void main()=>runApp(const Preview());
class Preview extends StatefulWidget{const Preview({super.key});@override State<Preview> createState()=>_State();}
class _State extends State<Preview>{String? decision;final now=DateTime.now().millisecondsSinceEpoch;@override Widget build(BuildContext context)=>MaterialApp(debugShowCheckedModeBanner:false,home:Scaffold(appBar:AppBar(title:const Text('P12 · lokale chauffeurdemo')),body:decision==null?DriverRideOfferPanel(offer:DriverRideOffer(id:'offline',version:1,vehicleId:'demo-vito',deadlineMs:now+30000,pickup:'Synthetisch ophaalpunt',destination:'Synthetische bestemming',requestedVehicleLabel:'Mercedes Vito',requestedChoiceKind:'exact'),nowMs:now,onDecision:(v)=>setState(()=>decision=v)):Center(child:Text(decision=='accept'?'Demo: chauffeur bevestigd · ETA blijft geschat tot NAV':'Demo: geweigerd · volgende kandidaat of centrale')))));}
