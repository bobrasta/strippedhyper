import 'package:flutter_test/flutter_test.dart';
import 'package:bienhypermed/models/notification.dart';

AppNotification _n(String type) => AppNotification.fromJson(
    {'id': 1, 'type': type, 'title': '', 'entity_type': 'expense', 'entity_id': 9});

void main() {
  test('expense notification types parse to expense types', () {
    expect(_n('expense_requested').type, NotificationType.expensePending);
    expect(_n('expense_escalated').type, NotificationType.expensePending);
    expect(_n('expense_approved').type, NotificationType.expenseApproved);
    expect(_n('expense_paid').type, NotificationType.expensePaid);
  });

  test('an unknown type is a plain system notice, not a service ticket', () {
    expect(_n('expense.submitted_manager').type, NotificationType.system);
    expect(_n('something_new').type, NotificationType.system);
  });
}
