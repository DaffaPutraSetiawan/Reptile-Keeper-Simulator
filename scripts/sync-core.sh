#!/bin/sh
# Salin core.js (logika game) ke Edge Function supaya browser & server memakai kode yang sama.
cd "$(dirname "$0")/.." && cp core.js supabase/functions/game/core.js && echo "core.js disalin ke supabase/functions/game/"
