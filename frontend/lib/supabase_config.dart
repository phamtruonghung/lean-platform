/// Supabase project configuration, baked in at build time.
///
/// These are public by design — an anon key is meant to ship inside a
/// browser bundle, the same way it would for any Supabase client app — so
/// they are read via `--dart-define`, not from a `.env` file the way the
/// backend's `DATABASE_URL` is: nothing on the client ever reads a dotenv
/// file, because there is no server process here to keep one off the wire.
/// See the root `.env.example` for the values themselves and
/// `README.md`'s Authentication section for where they come from.
///
///     flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
library;

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
