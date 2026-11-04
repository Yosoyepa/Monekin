// Android apps whose notifications are offered for reading (T002). Owner: w-avisos.
//
// Package names checked on 2026-11-04 against their Google Play listing
// (play.google.com/store/apps/details?id=<package> answers, it is not a 404),
// except where noted:
//  - Mi Bancolombia: co.com.bancolombia.personas.superapp. The old app
//    com.todo1.mobile was removed from Google Play on 2025-06-03 but phones may still have it.
//  - Davivienda: com.davivienda.daviviendaapp. DaviPlata: com.davivienda.daviplataapp.
//  - Nequi: com.nequi.MobileApp. BBVA Colombia: co.com.bbva.mb. Banco de Bogotá: com.bancodebogota.bancamovil.
//  - Nu: com.nu.production is the single Nu app (Brazil, Mexico and Colombia share it).
//  - com.google.android.apps.messaging is Google Messages: Bancolombia and Davivienda also send SMS.

/// Which template family reads the notifications of an app.
enum BankId {
  bancolombia,
  nequi,
  davivienda,
  daviplata,
  nu,
  bbva,
  bancoDeBogota,
}

class BankApp {
  const BankApp(this.name, this.package, {this.bank, this.preselected = true});

  final String name;
  final String package;

  /// Templates tried first for this app; null tries all of them (SMS apps).
  final BankId? bank;

  /// Watched by default when the user turns the reader on.
  final bool preselected;
}

const kKnownBankApps = <BankApp>[
  BankApp(
    'Bancolombia',
    'co.com.bancolombia.personas.superapp',
    bank: BankId.bancolombia,
  ),
  BankApp(
    'Bancolombia (app anterior)',
    'com.todo1.mobile',
    bank: BankId.bancolombia,
  ),
  BankApp('Nequi', 'com.nequi.MobileApp', bank: BankId.nequi),
  BankApp(
    'Davivienda',
    'com.davivienda.daviviendaapp',
    bank: BankId.davivienda,
  ),
  BankApp('Daviplata', 'com.davivienda.daviplataapp', bank: BankId.daviplata),
  BankApp('Nu', 'com.nu.production', bank: BankId.nu),
  BankApp('BBVA', 'co.com.bbva.mb', bank: BankId.bbva),
  BankApp(
    'Banco de Bogotá',
    'com.bancodebogota.bancamovil',
    bank: BankId.bancoDeBogota,
  ),
  BankApp(
    'Mensajes (SMS)',
    'com.google.android.apps.messaging',
    preselected: false,
  ),
];

Set<String> defaultWatchedPackages() => {
  for (final a in kKnownBankApps)
    if (a.preselected) a.package,
};

/// Known app for [package], or null for one typed by hand.
BankApp? bankAppFor(String package) {
  for (final a in kKnownBankApps) {
    if (a.package == package) return a;
  }
  return null;
}
