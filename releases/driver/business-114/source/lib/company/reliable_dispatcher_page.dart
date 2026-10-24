import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import '../customer_booking/reliable_choice_api.dart';
import 'reliable_dispatcher_panel.dart';

class ReliableDispatcherPageV1 extends StatelessWidget {
  const ReliableDispatcherPageV1({super.key,required this.api,required this.tenant,required this.company,required this.language});
  final ReliableChoiceApiV1 api;
  final String tenant,company;
  final AppLanguage language;
  String text(String nl,String en,String fr,String es,String de)=>LocalizedText(nl:nl,en:en,fr:fr,es:es,de:de).of(language);
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(text('Dispatch','Dispatch','Répartition','Despacho','Disposition'))),
    body:SingleChildScrollView(padding:const EdgeInsets.all(16),child:ReliableDispatcherPanelV1(api:api,tenant:tenant,company:company,language:language,
      selectAssignment:(row)async{
        final fresh=(row['candidates'] as List? ?? []).whereType<Map>().where((c)=>c['evidence_status']=='fresh'&&c['vehicle_id'] is String&&c['driver_id'] is String).toList();
        final manual=(row['manual_candidates'] as List? ?? []).whereType<Map>().where((c)=>c['evidence_status']=='manual_review'&&c['vehicle_id'] is String&&c['driver_id'] is String).toList();
        final candidates=fresh.isEmpty?manual:fresh;
        if(candidates.isEmpty)return null;
        return showDialog<({String vehicle,String driver})>(context:context,builder:(context)=>SimpleDialog(
          title:Text(fresh.isEmpty?text('Handmatige keuze — harde controles blijven gelden','Manual choice — hard checks apply','Choix manuel — contrôles obligatoires','Elección manual — controles obligatorios','Manuelle Auswahl — Prüfungen gelten'):text('Kies betrouwbare wagen','Choose reliable vehicle','Choisir un véhicule fiable','Elegir vehículo fiable','Zuverlässiges Fahrzeug wählen')),
          children:[for(final c in candidates)SimpleDialogOption(onPressed:()=>Navigator.pop(context,(vehicle:c['vehicle_id'] as String,driver:c['driver_id'] as String)),
            child:Text('${c['vehicle_id']} · ${c['driver_id']}'))]));
      })),
  );
}
