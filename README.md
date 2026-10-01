# Budget Tracker

Weekly budget and savings tracker — Flutter web app on Supabase, published to GitHub Pages.

**Live app:** https://yogielmo.github.io/yogender-budget-tracker/

## How it fits together

- `lib/` — the Flutter app
- `supabase/schema.sql` — database tables, security rules and starter data (already run on the Supabase project)
- `.github/workflows/deploy.yml` — on every push to `main`, GitHub builds the app and publishes it to Pages

## Budget model

- $600 weekly budget, split 50% Needs / 20% Wants / 30% Savings (editable)
- Payday is Tuesday; weeks start on Tuesday
- Money stored as whole cents
- Offline-first: entries save on the device and sync to Supabase when online (in progress)

## Run locally (on a computer)

```bash
flutter pub get
flutter run -d chrome
```
