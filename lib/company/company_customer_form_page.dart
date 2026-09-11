// COMPANY-CUSTOMER-OPS-P0A

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_customer_labels.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_customers_repository.dart';

const Key kCompanyCustomersSaveButtonKey = Key('company_customers_save');
const Key kCompanyCustomerFormPageKey = Key('company_customer_form_page');
const Key kCompanyCustomerFormNameKey = Key('company_customer_form_name');
const Key kCompanyCustomerFormEmailKey = Key('company_customer_form_email');

class CompanyCustomerFormPage extends StatefulWidget {
  const CompanyCustomerFormPage({
    super.key,
    required this.repository,
    this.existing,
    this.language,
  });

  final CompanyCustomersRepository repository;
  final CompanyCustomer? existing;
  final AppLanguage? language;

  @override
  State<CompanyCustomerFormPage> createState() => _CompanyCustomerFormPageState();
}

class _CompanyCustomerFormPageState extends State<CompanyCustomerFormPage> {
  late final TextEditingController _displayName;
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _callingCode;
  late final TextEditingController _locale;
  late final TextEditingController _companyName;
  late final TextEditingController _vat;
  late final TextEditingController _notes;
  final List<_AddressDraft> _addresses = <_AddressDraft>[];
  bool _saving = false;
  String? _formError;
  Map<String, String> _fieldErrors = const <String, String>{};

  AppLanguage get _lang => widget.language ?? appLanguageNotifier.value;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _displayName = TextEditingController(text: existing?.displayName ?? '');
    _firstName = TextEditingController(text: existing?.firstName ?? '');
    _lastName = TextEditingController(text: existing?.lastName ?? '');
    _email = TextEditingController(text: existing?.email ?? '');
    _phone = TextEditingController(text: existing?.phone ?? '');
    _callingCode = TextEditingController(
      text: existing?.countryCallingCode ?? '',
    );
    _locale = TextEditingController(text: existing?.locale ?? '');
    _companyName = TextEditingController(text: existing?.companyName ?? '');
    _vat = TextEditingController(text: existing?.vatNumber ?? '');
    _notes = TextEditingController(text: existing?.internalNotes ?? '');
    if (existing != null) {
      for (final address in existing.addresses) {
        _addresses.add(_AddressDraft.fromAddress(address));
      }
    }
  }

  @override
  void dispose() {
    _displayName.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    _callingCode.dispose();
    _locale.dispose();
    _companyName.dispose();
    _vat.dispose();
    _notes.dispose();
    for (final address in _addresses) {
      address.dispose();
    }
    super.dispose();
  }

  CompanyCustomerWrite _write() {
    return CompanyCustomerWrite(
      displayName: _displayName.text,
      firstName: _firstName.text,
      lastName: _lastName.text,
      email: _email.text,
      phone: _phone.text,
      countryCallingCode: _callingCode.text,
      locale: _locale.text,
      companyName: _companyName.text,
      vatNumber: _vat.text,
      internalNotes: _notes.text,
      addresses: [
        for (final address in _addresses) address.toAddress(),
      ],
    );
  }

  bool get _canSave {
    if (_saving) return false;
    return validateCompanyCustomerWrite(_write()).isEmpty;
  }

  Future<void> _save() async {
    if (_saving) return;
    final write = _write();
    final fields = validateCompanyCustomerWrite(write);
    if (fields.isNotEmpty) {
      setState(() {
        _fieldErrors = fields;
        _formError = fields.containsKey('contact') ||
                fields.containsKey('display_name')
            ? kCompanyCustomersContactRequired.of(_lang)
            : fields.containsKey('email')
            ? kCompanyCustomersInvalidEmail.of(_lang)
            : fields.containsKey('phone')
            ? kCompanyCustomersInvalidPhone.of(_lang)
            : kCompanyCustomersSaveFailed.of(_lang);
      });
      return;
    }
    setState(() {
      _saving = true;
      _formError = null;
      _fieldErrors = const <String, String>{};
    });
    try {
      if (widget.existing == null) {
        final result = await widget.repository.create(write);
        if (!mounted) return;
        Navigator.of(context).pop(result);
        return;
      }
      final updated = await widget.repository.update(
        widget.existing!.customerId,
        write,
        revision: widget.existing!.revision,
      );
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } on CompanyCustomerException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _fieldErrors = error.fields;
        _formError = error.code == 'revision_conflict'
            ? kCompanyCustomersConflict.of(_lang)
            : error.offline
            ? kCompanyCustomersOffline.of(_lang)
            : kCompanyCustomersSaveFailed.of(_lang);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = kCompanyCustomersSaveFailed.of(_lang);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.existing == null
        ? kCompanyCustomersAddLabel.of(_lang)
        : kCompanyCustomersEdit.of(_lang);
    return Scaffold(
      key: kCompanyCustomerFormPageKey,
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  TextField(
                    key: kCompanyCustomerFormNameKey,
                    controller: _displayName,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: kCompanyCustomersDisplayName.of(_lang),
                      errorText: _fieldErrors['display_name'] == null
                          ? null
                          : kCompanyCustomersContactRequired.of(_lang),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _firstName,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: kCompanyCustomersFirstName.of(_lang),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _lastName,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: kCompanyCustomersLastName.of(_lang),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: kCompanyCustomerFormEmailKey,
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: kCompanyCustomersEmail.of(_lang),
                      errorText: _fieldErrors['email'] == null
                          ? null
                          : kCompanyCustomersInvalidEmail.of(_lang),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _callingCode,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: kCompanyCustomersCallingCode.of(_lang),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: kCompanyCustomersPhone.of(_lang),
                      errorText: _fieldErrors['phone'] == null
                          ? null
                          : kCompanyCustomersInvalidPhone.of(_lang),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _locale,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: kCompanyCustomersLocale.of(_lang),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _companyName,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: kCompanyCustomersCompanyName.of(_lang),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _vat,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: kCompanyCustomersVat.of(_lang),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    kCompanyCustomersAddresses.of(_lang),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < _addresses.length; i += 1)
                    _AddressEditor(
                      draft: _addresses[i],
                      onRemove: () {
                        setState(() {
                          _addresses.removeAt(i).dispose();
                        });
                      },
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        setState(() => _addresses.add(_AddressDraft()));
                      },
                      icon: const Icon(Icons.add),
                      label: Text(kCompanyCustomersAddAddress.of(_lang)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notes,
                    minLines: 3,
                    maxLines: 6,
                    decoration: InputDecoration(
                      labelText: kCompanyCustomersInternalNotes.of(_lang),
                      alignLabelWithHint: true,
                    ),
                  ),
                  if (_formError != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _formError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: kCompanyCustomersSaveButtonKey,
                  onPressed: _canSave ? _save : null,
                  child: Text(kCompanyCustomersSave.of(_lang)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddressDraft {
  _AddressDraft({
    this.addressId = '',
    this.type = 'other',
    String line1 = '',
    String city = '',
    String postalCode = '',
    String countryCode = '',
  }) : line1 = TextEditingController(text: line1),
       city = TextEditingController(text: city),
       postalCode = TextEditingController(text: postalCode),
       countryCode = TextEditingController(text: countryCode);

  factory _AddressDraft.fromAddress(CompanyCustomerAddress address) {
    return _AddressDraft(
      addressId: address.addressId,
      type: address.type,
      line1: address.line1,
      city: address.city,
      postalCode: address.postalCode,
      countryCode: address.countryCode,
    );
  }

  final String addressId;
  String type;
  final TextEditingController line1;
  final TextEditingController city;
  final TextEditingController postalCode;
  final TextEditingController countryCode;

  CompanyCustomerAddress toAddress() {
    return CompanyCustomerAddress(
      addressId: addressId,
      type: type,
      line1: line1.text,
      city: city.text,
      postalCode: postalCode.text,
      countryCode: countryCode.text,
    );
  }

  void dispose() {
    line1.dispose();
    city.dispose();
    postalCode.dispose();
    countryCode.dispose();
  }
}

class _AddressEditor extends StatelessWidget {
  const _AddressEditor({required this.draft, required this.onRemove});

  final _AddressDraft draft;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: draft.type,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: const [
                      DropdownMenuItem(value: 'home', child: Text('home')),
                      DropdownMenuItem(value: 'work', child: Text('work')),
                      DropdownMenuItem(value: 'pickup', child: Text('pickup')),
                      DropdownMenuItem(value: 'billing', child: Text('billing')),
                      DropdownMenuItem(value: 'other', child: Text('other')),
                    ],
                    onChanged: (value) {
                      if (value != null) draft.type = value;
                    },
                  ),
                ),
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            TextField(
              controller: draft.line1,
              decoration: const InputDecoration(labelText: 'line1'),
            ),
            TextField(
              controller: draft.city,
              decoration: const InputDecoration(labelText: 'city'),
            ),
            TextField(
              controller: draft.postalCode,
              decoration: const InputDecoration(labelText: 'postal_code'),
            ),
            TextField(
              controller: draft.countryCode,
              decoration: const InputDecoration(labelText: 'country_code'),
            ),
          ],
        ),
      ),
    );
  }
}
