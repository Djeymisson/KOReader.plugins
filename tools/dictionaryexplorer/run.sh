#!/bin/sh
# Runs the Dictionary Explorer tests and benchmarks inside a real KOReader,
# without a window and without touching your KOReader settings, history or
# dictionaries (everything happens in a temporary profile).
#
#   tools/dictionaryexplorer/run.sh [options] SUITE...
#
# SUITE is the name of a file in suites/ (without .lua), "unit" for the tests
# that need no KOReader, or "check" for everything that passes or fails
# (unit, contract, regression, budgets). See README.md for what each does.
#
# Options:
#   --koreader DIR   KOReader install to run (default: $KOREADER_DIR, or /usr/lib/koreader)
#   --dicts DIR      StarDict dictionaries to use (default: $DICT_DIR, or ~/.config/koreader/data/dict)
#   --keep           keep the temporary profile (it is printed) to look at its screenshots and log
#   --timeout SECS   give up on a suite after this long (default: 240)
#
# Exit status: 0 if every suite passed, 1 if a check failed or a suite did not finish.

set -u

TOOLS=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$TOOLS/../.." && pwd)
PLUGIN="$ROOT/dictionaryexplorer.koplugin"
KOREADER_DIR=${KOREADER_DIR:-/usr/lib/koreader}
DICT_DIR=${DICT_DIR:-$HOME/.config/koreader/data/dict}
TIMEOUT=240
KEEP=0
SUITES=""

while [ $# -gt 0 ]; do
	case "$1" in
		--koreader) KOREADER_DIR=$2; shift 2 ;;
		--dicts) DICT_DIR=$2; shift 2 ;;
		--timeout) TIMEOUT=$2; shift 2 ;;
		--keep) KEEP=1; shift ;;
		-h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		-*) echo "unknown option: $1" >&2; exit 2 ;;
		*) SUITES="$SUITES $1"; shift ;;
	esac
done

[ -n "$SUITES" ] || { echo "usage: $0 [options] SUITE...  (try --help)" >&2; exit 2; }
[ -x "$KOREADER_DIR/reader.lua" ] || { echo "no KOREADER at $KOREADER_DIR (use --koreader)" >&2; exit 2; }
[ -d "$PLUGIN" ] || { echo "plugin not found at $PLUGIN" >&2; exit 2; }

# "check" stands for every suite that passes or fails.
case " $SUITES " in *" check "*) SUITES=$(echo "$SUITES" | sed 's/\bcheck\b/unit contract regression budgets/') ;; esac

LUAJIT="$KOREADER_DIR/luajit"
[ -x "$LUAJIT" ] || LUAJIT=$(command -v luajit || true)

overall=0

run_unit() {
	[ -n "$LUAJIT" ] || { echo "unit: no luajit found" >&2; return 1; }
	status=0
	for test in "$TOOLS"/unit/*_test.lua; do
		echo "== unit: $(basename "$test" .lua)"
		DE_PLUGIN="$PLUGIN" "$LUAJIT" "$test" || status=1
		echo
	done
	return $status
}

run_suite() {
	name=$1
	file="$TOOLS/suites/$name.lua"
	[ -f "$file" ] || { echo "no such suite: $name (see suites/)" >&2; return 1; }

	work=$(mktemp -d "${TMPDIR:-/tmp}/dictionaryexplorer-tools.XXXXXX")
	mkdir -p "$work/home/plugins/zzharness.koplugin" "$work/home/data" "$work/out"
	ln -s "$PLUGIN" "$work/home/plugins/dictionaryexplorer.koplugin"
	ln -s "$DICT_DIR" "$work/home/data/dict"
	cp "$TOOLS/lib/launcher.lua" "$work/home/plugins/zzharness.koplugin/main.lua"
	echo 'return { fullname = "Dictionary Explorer test harness", description = "Runs a suite, then quits." }' > "$work/home/plugins/zzharness.koplugin/_meta.lua"
	# A book to open, since the plugin's features live in the reader; the
	# statistics plugin is off because it asks about its database on first use.
	printf 'Minha casa fica perto de uma livraria.\nThe house is near a bookshop.\n' > "$work/book.txt"
	printf 'return { ["plugins_disabled"] = { ["statistics"] = true }, ["color_rendering"] = false }\n' > "$work/home/settings.reader.lua"

	echo "== $name"
	( cd "$KOREADER_DIR" && \
		DE_TOOLS="$TOOLS" DE_SUITE="$file" DE_OUT="$work/out" \
		KO_HOME="$work/home" KO_MULTIUSER=1 SDL_VIDEODRIVER=dummy LC_ALL=en_US.UTF-8 \
		timeout "$TIMEOUT" ./reader.lua "$work/book.txt" > "$work/out/koreader.log" 2>&1 )
	status=$?

	[ -f "$work/out/report.txt" ] && cat "$work/out/report.txt"
	result=$(grep '^RESULT ' "$work/out/report.txt" 2>/dev/null | tail -1)
	if [ -z "$result" ]; then
		echo "!! $name did not finish (exit $status). Last lines of KOReader's log:" >&2
		grep -av '^ERROR: Couldn.t open /dev/input' "$work/out/koreader.log" | tail -15 >&2
		outcome=1
	else
		case "$result" in *"failed=0"*) outcome=0 ;; *) outcome=1 ;; esac
		skipped=$(echo "$result" | sed -n 's/.*skipped=\([0-9][0-9]*\).*/\1/p')
		if [ "${skipped:-0}" -gt 0 ]; then
			echo "note: $skipped check(s) were skipped (see the SKIP lines above): a dictionary the suite looks for is not in $DICT_DIR" >&2
		fi
	fi

	if [ "$KEEP" = 1 ]; then echo "(kept: $work)"; else rm -rf "$work"; fi
	return $outcome
}

for suite in $SUITES; do
	if [ "$suite" = unit ]; then run_unit; else run_suite "$suite"; fi
	[ $? -eq 0 ] || overall=1
	echo
done

[ $overall -eq 0 ] && echo "ALL PASSED" || echo "SOMETHING FAILED"
exit $overall
