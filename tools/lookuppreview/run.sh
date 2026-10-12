#!/bin/sh
# Runs the Lookup Preview tests inside a real KOReader, without a window and
# without touching your KOReader settings, history or dictionaries (everything
# happens in a temporary profile).
#
#   tools/lookuppreview/run.sh [options] SUITE...
#
# SUITE is the name of a file in suites/ (without .lua), or "check" for every
# suite (entry, dictionary, scroll, online, vocabulary, navigation, reading,
# settings, l10n). See README.md for what each does. The
# synthetic dictionaries of tools/dictionaryexplorer/fixtures are always there,
# and the translation service and Wikipedia are replaced by stand-ins, so no
# suite needs a dictionary of your own or the network.
#
# Options:
#   --koreader DIR   KOReader install to run (default: $KOREADER_DIR, or /usr/lib/koreader;
#                    on macOS, the Contents/koreader folder of KOReader.app)
#   --keep           keep the temporary profile (it is printed) to look at its log
#   --timeout SECS   give up on a suite after this long (default: 120)
#
# LP_LANGUAGE=pt_BR runs the suites with KOReader in that language (the l10n
# suite always runs in pt_BR).
#
# Exit status: 0 if every suite passed, 1 if a check failed or a suite did not finish.

set -u

TOOLS=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$TOOLS/../.." && pwd)
PLUGIN="$ROOT/lookuppreview.koplugin"
FIXTURES="$ROOT/tools/dictionaryexplorer/fixtures/make.lua"
KOREADER_DIR=${KOREADER_DIR:-/usr/lib/koreader}
TIMEOUT=120
KEEP=0
SUITES=""

while [ $# -gt 0 ]; do
	case "$1" in
		--koreader) KOREADER_DIR=$2; shift 2 ;;
		--timeout) TIMEOUT=$2; shift 2 ;;
		--keep) KEEP=1; shift ;;
		-h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		-*) echo "unknown option: $1" >&2; exit 2 ;;
		*) SUITES="$SUITES $1"; shift ;;
	esac
done

[ -n "$SUITES" ] || { echo "usage: $0 [options] SUITE...  (try --help)" >&2; exit 2; }
[ -f "$KOREADER_DIR/reader.lua" ] || { echo "no KOReader at $KOREADER_DIR (use --koreader)" >&2; exit 2; }
[ -d "$PLUGIN" ] || { echo "plugin not found at $PLUGIN" >&2; exit 2; }
[ -f "$FIXTURES" ] || { echo "fixture generator not found at $FIXTURES" >&2; exit 2; }

expanded=""
for suite in $SUITES; do
	if [ "$suite" = check ]; then
		expanded="$expanded entry dictionary scroll online vocabulary navigation reading settings l10n"
	else
		expanded="$expanded $suite"
	fi
done
SUITES=$expanded

LUAJIT="$KOREADER_DIR/luajit"
[ -x "$LUAJIT" ] || LUAJIT=$(command -v luajit || true)
[ -n "$LUAJIT" ] || { echo "no luajit found" >&2; exit 2; }

# reader.lua is its own script on Linux (#!./luajit), but not in the macOS app.
if [ -x "$KOREADER_DIR/reader.lua" ]; then
	START_READER="./reader.lua"
else
	START_READER="./luajit reader.lua"
fi
# GNU timeout is not part of macOS (Homebrew's coreutils has it).
TIMEOUT_CMD=""
if command -v timeout > /dev/null 2>&1; then
	TIMEOUT_CMD="timeout $TIMEOUT"
elif command -v gtimeout > /dev/null 2>&1; then
	TIMEOUT_CMD="gtimeout $TIMEOUT"
fi

overall=0

run_suite() {
	name=$1
	file="$TOOLS/suites/$name.lua"
	[ -f "$file" ] || { echo "no such suite: $name (see suites/)" >&2; return 1; }

	work=$(mktemp -d "${TMPDIR:-/tmp}/lookuppreview-tools.XXXXXX")
	mkdir -p "$work/home/plugins/zzharness.koplugin" "$work/home/data/dict" "$work/out" "$work/unused"
	ln -s "$PLUGIN" "$work/home/plugins/lookuppreview.koplugin"
	"$LUAJIT" "$FIXTURES" "$work/home/data/dict/fixtures" "$work/unused" > /dev/null \
		|| { echo "!! could not make the fixtures" >&2; rm -rf "$work"; return 1; }
	cp "$TOOLS/lib/launcher.lua" "$work/home/plugins/zzharness.koplugin/main.lua"
	echo 'return { fullname = "Lookup Preview test harness", description = "Runs a suite, then quits." }' > "$work/home/plugins/zzharness.koplugin/_meta.lua"
	# A book with words the fixtures have: "livro" (Fixture Text), "casa"
	# (Fixture XDXF), "house" (Fixture HTML); "qqqzzzz" is in none.
	printf 'O livro fica na casa qqqzzzz.\nThe house is near a bookshop.\n' > "$work/book.txt"
	# The l10n suite runs KOReader in Brazilian Portuguese; the others in
	# English, or in the language LP_LANGUAGE names (pt_BR, de...).
	language=""
	[ -n "${LP_LANGUAGE:-}" ] && language="[\"language\"] = \"$LP_LANGUAGE\", "
	[ "$name" = l10n ] && language='["language"] = "pt_BR", '
	printf 'return { %s["plugins_disabled"] = { ["statistics"] = true }, ["color_rendering"] = false }\n' "$language" > "$work/home/settings.reader.lua"

	echo "== $name"
	( cd "$KOREADER_DIR" && \
		LP_TOOLS="$TOOLS" LP_SUITE="$file" LP_OUT="$work/out" \
		KO_HOME="$work/home" KO_MULTIUSER=1 SDL_VIDEODRIVER=dummy LC_ALL=en_US.UTF-8 \
		$TIMEOUT_CMD $START_READER "$work/book.txt" > "$work/out/koreader.log" 2>&1 )
	status=$?

	[ -f "$work/out/report.txt" ] && cat "$work/out/report.txt"
	result=$(grep '^RESULT ' "$work/out/report.txt" 2>/dev/null | tail -1)
	if [ -z "$result" ]; then
		echo "!! $name did not finish (exit $status). Last lines of KOReader's log:" >&2
		grep -av '^ERROR: Couldn.t open /dev/input' "$work/out/koreader.log" | tail -15 >&2
		outcome=1
	else
		case "$result" in *"failed=0"*) outcome=0 ;; *) outcome=1 ;; esac
	fi

	if [ "$KEEP" = 1 ]; then echo "(kept: $work)"; else rm -rf "$work"; fi
	return $outcome
}

for suite in $SUITES; do
	run_suite "$suite" || overall=1
	echo
done

[ $overall -eq 0 ] && echo "ALL PASSED" || echo "SOMETHING FAILED"
exit $overall
