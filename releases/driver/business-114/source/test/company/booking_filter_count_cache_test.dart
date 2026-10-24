import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/booking_list_page_repository.dart';
void main() {
 test('company open list requests all lifecycle rows while driver stays operational', () {
  BookingListPageRequest request(BookingListActor actor) => BookingListPageRequest(
    actor:actor,tenantId:'mario',companyId:'mario',historyMode:BookingListHistoryMode.active);
  expect(buildBookingListPageQuery(request:request(BookingListActor.company),limit:50)['include_history'],'1');
  expect(buildBookingListPageQuery(request:request(BookingListActor.driver),limit:50)['include_history'],isNull);
 });
 test('history cannot replace active count, and other companies stay isolated', () {
  final cache = BookingFilterCountCache();
  cache.record(scope:'mario', mode:BookingListHistoryMode.active, counts:{'open':3,'completed':0}, hasMore:false);
  cache.record(scope:'mario', mode:BookingListHistoryMode.history, counts:{'open':8,'completed':0}, hasMore:false);
  expect(cache.label('mario','open'),'3');
  expect(cache.label('mario','completed'),'0');
  expect(cache.label('fluxidi','open'),'—');
 });
 test('unknown and partially loaded counts are never claimed as exact totals', () {
  final cache = BookingFilterCountCache();
  expect(cache.label('mario','open'),'—');
  cache.record(scope:'mario',mode:BookingListHistoryMode.active,counts:{'open':3},hasMore:true);
  expect(cache.label('mario','open'),'3+');
 });
}
