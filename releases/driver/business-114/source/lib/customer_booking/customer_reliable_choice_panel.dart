import 'dart:async';
import 'package:flutter/material.dart';
import 'reliable_choice_api.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'customer_reliable_choice.dart';
import 'customer_booking_vehicle_cards.dart';
import 'customer_booking_vehicle_offers.dart';

/// Public Reliable Choice transport and cards for an existing authorised
/// booking. The caller owns the payment flow and session. This never starts
/// live GPS/tracking; only server status after NAV may announce it.
class CustomerReliableChoicePanelV1 extends StatefulWidget {
  const CustomerReliableChoicePanelV1({super.key,required this.api,required this.bookingId,required this.language,required this.palette,this.choiceKind='exact',this.nowMs,this.statusOnly=false});
  final ReliableChoiceApiV1 api;
  final String bookingId, choiceKind;
  final AppLanguage language;
  final CustomerThemePalette palette;
  final int Function()? nowMs;
  final bool statusOnly;
  @override State<CustomerReliableChoicePanelV1> createState()=>_ChoiceState();
}
class _ChoiceState extends State<CustomerReliableChoicePanelV1> {
  List<CustomerBookingVehicleOffer> _offers=[];
  String? _selected;
  String? _state;
  bool _loading=true,_failed=false,_choosing=false;
  Timer? _poll;
  int _generation=0;
  @override void initState(){super.initState();unawaited(_load());}
  @override void didUpdateWidget(covariant CustomerReliableChoicePanelV1 old){super.didUpdateWidget(old);if(old.api!=widget.api||old.bookingId!=widget.bookingId){_poll?.cancel();_selected=null;_state=null;unawaited(_load());}}
  @override void dispose(){_generation++;_poll?.cancel();super.dispose();}
  Future<void> _load()async{
    final generation=++_generation;setState((){_loading=true;_failed=false;});
    if(widget.statusOnly){setState(()=>_loading=false);_poll?.cancel();_poll=Timer.periodic(const Duration(seconds:2),(_)=>unawaited(_status()));await _status();return;}
    try{
      final rows=await widget.api.vehicles(widget.bookingId,nowMs:widget.nowMs?.call());
      if(!mounted||generation!=_generation)return;
      setState((){_offers=rows.map((r)=>CustomerBookingVehicleOffer(vehicle:{'vehicle_id':r['vehicle_id'],'name':r['vehicle_name'],'vehicle_type':r['vehicle_type'],'category':r['vehicle_category'],'tier':r['vehicle_category'],'photo_url':r['photo_url'],'passenger_capacity':r['passenger_capacity'],'luggage_capacity':r['luggage_capacity'],'reliable_choice_v1':r},passengerSeats:r['passenger_capacity'] as int?,baggageCapacity:r['luggage_capacity'] as int?)).toList();_loading=false;if(rows.isEmpty)_state='dispatcher_review';});
    }catch(_){if(mounted&&generation==_generation)setState((){_offers=[];_loading=false;_failed=true;});}
  }
  Future<void> _choose(CustomerBookingVehicleOffer offer)async{
    if(_choosing)return;
    final evidence=CustomerReliableChoiceEstimate.parse(offer.vehicle['reliable_choice_v1'],vehicleId:offer.vehicleId,nowMs:widget.nowMs?.call());
    if(evidence==null){await _load();return;}
    final generation=_generation;setState(()=>_choosing=true);
    try{
      await widget.api.choose(widget.bookingId,offer.vehicleId,kind:widget.choiceKind);
      if(!mounted||generation!=_generation)return;
      setState((){_selected=offer.vehicleId;_state='waiting_driver_confirmation';});
      _poll?.cancel();_poll=Timer.periodic(const Duration(seconds:2),(_)=>unawaited(_status()));await _status();
    }catch(_){if(mounted&&generation==_generation)setState(()=>_failed=true);}
    finally{if(mounted&&generation==_generation)setState(()=>_choosing=false);}
  }
  bool _statusBusy=false;
  Future<void> _status()async{
    if(_statusBusy)return;_statusBusy=true;final generation=_generation;
    try{final status=await widget.api.status(widget.bookingId);if(!mounted||generation!=_generation)return;setState((){_failed=false;_state=status['live_tracking']==true?'live_tracking':status['state'] as String?;});if(['live_tracking','cancelled','completed','stopped'].contains(_state))_poll?.cancel();}
    catch(_){if(mounted&&generation==_generation)setState(()=>_failed=true);}finally{_statusBusy=false;}
  }
  String _copy(String nl,String en,String fr,String es,String de)=>LocalizedText(nl:nl,en:en,fr:fr,es:es,de:de).of(widget.language);
  @override Widget build(BuildContext context){
    if(_loading)return const Center(child:CircularProgressIndicator(key:ValueKey('p20-list-loading')));
    if(_failed)return Column(children:[Text(_copy('Beschikbaarheid kon niet worden geladen','Availability could not be loaded','Disponibilité indisponible','No se pudo cargar la disponibilidad','Verfügbarkeit konnte nicht geladen werden')),TextButton(key:const ValueKey('p20-retry'),onPressed:_selected==null?_load:_status,child:Text(_copy('Opnieuw proberen','Try again','Réessayer','Reintentar','Erneut versuchen')))]);
    return Column(children:[
      if(_state!=null)Text(_state=='live_tracking'?_copy('Live tracking gestart','Live tracking started','Suivi en direct démarré','Seguimiento en directo iniciado','Live-Tracking gestartet'):customerReliableChoiceStatus(_state!,widget.language),key:const ValueKey('p20-choice-status')),
      if(!widget.statusOnly&&_selected==null&&_offers.isNotEmpty)AbsorbPointer(absorbing:_choosing,child:CustomerBookingVehiclePhotoCardGrid(offers:_offers,language:widget.language,palette:widget.palette,selectedVehicleId:_selected,reliableChoiceOnly:true,onSelected:_choose)),
      if(_selected!=null)Text(CustomerReliableChoiceEstimate.parse(_offers.firstWhere((o)=>o.vehicleId==_selected).vehicle['reliable_choice_v1'],vehicleId:_selected!,nowMs:widget.nowMs?.call())?.etaLabel(widget.language)??_copy('ETA opnieuw beoordelen','ETA needs refresh','Arrivée à réévaluer','Revisar hora de llegada','Ankunft neu prüfen')),
    ]);
  }
}
