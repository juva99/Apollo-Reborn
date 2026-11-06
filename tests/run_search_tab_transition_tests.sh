#!/bin/sh
set -eu

test_repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_build_dir=$(mktemp -d "${TMPDIR:-/tmp}/apollo-search-tab-transition.XXXXXX")
trap 'rm -rf -- "$test_build_dir"' EXIT HUP INT TERM

python3 - "$test_repo_root" "$test_build_dir" <<'PY'
from pathlib import Path
import sys

root, build = map(Path, sys.argv[1:])
source = (root / 'src/ApolloSearchTabFixes.xm').read_text()
start = source.index('@interface ApolloSearchTabTransitionShield')
end = source.index('// Apollo requires an exact top-offset match', start)
fixture = (root / 'tests/search_tab_transition_tests.m').read_text()
hook = source[source.index('%hook ApolloSearchTabSceneDelegate'):]
method = hook[hook.index('- (BOOL)tabBarController:'):hook.index('    // Google mode')]
method = method.replace('%orig(tabs, page)', '[self nativeShouldSelect:tabs page:page]')
method = method.replace('objc_getClass("_TtC6Apollo20SearchViewController")', 'QASearchController.class')
(build / 'search_tab_transition_tests.m').write_text(
    fixture.replace('// PRODUCTION_SOURCE', source[start:end])
           .replace('// PRODUCTION_RESELECT', method + '    return NO;\n}\n'))
PY

xcrun --sdk macosx clang -fobjc-arc -fblocks -Wall -Wextra -Werror \
    -framework Foundation -framework CoreGraphics \
    "$test_build_dir/search_tab_transition_tests.m" \
    -o "$test_build_dir/search_tab_transition_tests"
"$test_build_dir/search_tab_transition_tests"
