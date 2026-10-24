import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import '../customer_booking/reliable_choice_api.dart';

/// Existing authenticated company queue + atomic assignment API. The caller
/// uses its existing fleet picker; a shortlist is advisory, never authority.
class ReliableDispatcherPanelV1 extends StatefulWidget {
 const ReliableDispatcherPanelV1({super.key,required this.api,required this.tenant,required this.company,required this.language,required this.selectAssignment});
 final ReliableChoiceApiV1 api;
 final String tenant,company;
 final AppLanguage language;
 final Future<({String vehicle,String driver})?> Function(Map<String,dynamic> booking) selectAssignment;
 @override State<ReliableDispatcherPanelV1> createState()=>_QueueState();
}
class _QueueState extends State<ReliableDispatcherPanelV1>{
 List<Map<String,dynamic>> _rows=[];bool _loading=true,_failed=false,_assigning=false;int _generation=0;
 @override void initState(){super.initState();_load();}
 @override void didUpdateWidget(covariant ReliableDispatcherPanelV1 old){super.didUpdateWidget(old);if(old.api!=widget.api||old.tenant!=widget.tenant||old.company!=widget.company)_load();}
 @override void dispose(){_generation++;super.dispose();}
 Future<void> _load()async{final generation=++_generation;setState((){_loading=true;_failed=false;});try{final rows=await widget.api.dispatcherQueue(widget.tenant,widget.company);if(mounted&&generation==_generation)setState((){_rows=rows;_loading=false;});}catch(_){if(mounted&&generation==_generation)setState((){_loading=false;_failed=true;});}}
 Future<void> _assign(Map<String,dynamic> row)async{if(_assigning)return;final generation=_generation;setState(()=>_assigning=true);try{final choice=await widget.selectAssignment(Map<String,dynamic>.unmodifiable(row));if(!mounted||generation!=_generation||choice==null)return;await widget.api.manualAssign(row['booking_id'] as String,widget.tenant,widget.company,choice.vehicle,choice.driver,leg:row['assignment_leg'] as String?);await _load();}catch(_){if(mounted)setState(()=>_failed=true);}finally{if(mounted)setState(()=>_assigning=false);}}
 String _text(String nl,String en,String fr,String es,String de)=>LocalizedText(nl:nl,en:en,fr:fr,es:es,de:de).of(widget.language);
 String _reason(String? reason)=>switch(reason){
  'exact_vehicle_unavailable'=>_text('Gekozen wagen niet beschikbaar','Chosen vehicle unavailable','Véhicule choisi indisponible','Vehículo elegido no disponible','Gewähltes Fahrzeug nicht verfügbar'),
  'offer_limit'=>_text('Geen chauffeur heeft bevestigd','No driver has confirmed','Aucun chauffeur n’a confirmé','Ningún conductor ha confirmado','Kein Fahrer hat bestätigt'),
  'total_wait_limit'=>_text('Wachttijd verstreken','Waiting time expired','Temps d’attente dépassé','Tiempo de espera agotado','Wartezeit abgelaufen'),
  'no_reliable_candidates'=>_text('Geen betrouwbare wagen beschikbaar','No reliable vehicle available','Aucun véhicule fiable disponible','No hay vehículo fiable disponible','Kein zuverlässiges Fahrzeug verfügbar'),
  _=>_text('Handmatige controle nodig','Manual review needed','Vérification manuelle nécessaire','Revisión manual necesaria','Manuelle Prüfung erforderlich')};
 String _requirements(Map<String,dynamic> row){
  final r=row['requirements'] as Map? ?? {};
  final special=(r['capabilities'] as List? ?? []).whereType<String>().map((c)=>switch(c){
    'wheelchair'=>_text('rolstoel','wheelchair','fauteuil roulant','silla de ruedas','Rollstuhl'),
    'child_seat'=>_text('kinderzitje','child seat','siège enfant','asiento infantil','Kindersitz'),
    _=>c.replaceAll('_',' ')}).join(', ');
  return '${r['passengers']??'—'} ${_text('passagiers','passengers','passagers','pasajeros','Fahrgäste')} · ${r['luggage']??'—'} ${_text('koffers','bags','bagages','maletas','Gepäck')}${special.isEmpty?'':' · $special'}';
 }
 String _deadline(Map row){final value=row['deadline_at'];if(value is! num||!value.isFinite)return '';final at=DateTime.fromMillisecondsSinceEpoch(value.toInt()).toLocal();return '${_text('Bevestigen vóór','Confirm before','Confirmer avant','Confirmar antes de','Bestätigen vor')} ${at.hour.toString().padLeft(2,'0')}:${at.minute.toString().padLeft(2,'0')}';}
 String _eta(Map c){final band=c['eta_range_seconds'],meters=c['distance_meters'];if(band is! List||band.length!=2||band.any((n)=>n is! num)||meters is! num)return _text('Nieuwe controle nodig','Fresh check needed','Nouvelle vérification nécessaire','Nueva comprobación necesaria','Neue Prüfung erforderlich');final low=((band[0] as num)/60).ceil(),high=((band[1] as num)/60).ceil(),distance=(meters/1000).toStringAsFixed(1);return '±$low${high==low?'':'–$high'} min · ${widget.language==AppLanguage.nl?distance.replaceAll('.',','):distance} km';}
 List<Map> _manualCandidates(Map row)=>(row['manual_candidates'] as List? ?? []).whereType<Map>().where((c)=>c['evidence_status']=='manual_review'&&c['vehicle_id'] is String&&c['driver_id'] is String).toList();
 String _journey(Map row){final stops=(row['stops'] as List? ?? []).whereType<String>().join(' → '),ret=row['return_info'] as Map?;return [if(stops.isNotEmpty)stops,if(ret?['enabled']==true)'${_text('Retour','Return','Retour','Regreso','Rückfahrt')}: ${ret?['pickup_time']??''} ${ret?['pickup']??''} → ${ret?['destination']??''}'].join('\n');}
 List<Map> _candidates(Map row)=>(row['candidates'] as List? ?? []).whereType<Map>().where((c)=>c['evidence_status']=='fresh').toList();
 @override Widget build(BuildContext context){if(_loading)return const CircularProgressIndicator();return Column(children:[
  if(_failed)Text(_text('Toewijzing of ophalen mislukt','Assignment or retrieval failed','Échec de chargement ou affectation','Error al cargar o asignar','Laden oder Zuweisung fehlgeschlagen')),
  if(_rows.isEmpty&&!_failed)Text(_text('Geen ritten wachten op dispatch','No trips waiting for dispatch','Aucune course en attente','No hay viajes pendientes','Keine Fahrten warten')),
  for(final row in _rows)Card(child:ListTile(title:Text('${row['booking_id']}${row['assignment_leg']=='return'?' · ${_text('Retour','Return','Retour','Regreso','Rückfahrt')}':''}'),subtitle:Text('${row['pickup_summary']??''} → ${row['destination_summary']??''}\n${_reason(row['reason'] as String?)} · ${row['requested_vehicle']?['vehicle_id']??row['requested_vehicle']?['category']??''}\n${_journey(row)}\n${_requirements(row)}\n${_deadline(row)}\n${_candidates(row).isEmpty?_text('Betrouwbare shortlist ontbreekt. Controleer de rit.','Reliable shortlist unavailable. Review the ride.','Liste fiable indisponible. Vérifiez la course.','Lista fiable no disponible. Revise el viaje.','Zuverlässige Auswahlliste fehlt. Fahrt prüfen.'):_candidates(row).map((c)=>'${c['vehicle_id']}: ${_eta(c)}').join('\n')}'),trailing:TextButton(key:ValueKey('p20-assign-${row['booking_id']}'),onPressed:_assigning||(_candidates(row).isEmpty&&_manualCandidates(row).isEmpty)?null:()=>_assign(row),child:Text(_text('Toewijzen','Assign','Affecter','Asignar','Zuweisen'))))),
  TextButton(onPressed:_load,child:Text(_text('Vernieuwen','Refresh','Actualiser','Actualizar','Aktualisieren'))),
 ]);}
}
