import 'package:flutter/material.dart';
import 'package:inknest_notes/auth/account_agreements.dart';

class AccountLegalScreen extends StatelessWidget {
  const AccountLegalScreen({super.key, required this.document});

  final AccountLegalDocument document;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(document.title)),
      body: SafeArea(
        top: false,
        child: SelectionArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
            children: [
              Text(
                document.title,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '版本 ${document.version} · 生效日期 $currentAgreementEffectiveDate',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              for (final section in document.sections) ...[
                Text(
                  section.heading,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(section.body),
                const SizedBox(height: 20),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> openAccountLegalDocument(
  BuildContext context,
  AccountLegalDocument document,
) => Navigator.of(context).push<void>(
  MaterialPageRoute(builder: (_) => AccountLegalScreen(document: document)),
);
