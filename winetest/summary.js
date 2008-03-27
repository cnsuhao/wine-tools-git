result_window = null;
document.writeln ('<a href="#" onClick="open_popup(); return false;">Open popup</a>');

function open_popup () {
    result_window = window.open("/resultform.html","results","width=240,height=240,resizable,scrollbars=no");
}

function isopen () {
    return result_window && result_window.document && result_window.document.results;
}

function refresh (test, version, tests, todo, errors, skipped) {
    if (isopen ()) {
        var form = result_window.document.results;
        form.test.value = test;
        form.version.value = version;
        form.tests.value = tests;
        form.todo.value = todo;
        form.errors.value = errors;
        form.skipped.value = skipped;
        result_window.focus ();
    }
}

function clone () {
    if (isopen ()) {
        var cw = window.open("/resultform.html","frozen","width=200,height=140,resizable,scrollbars=no");
        var cf = cw.document.results;
        var rf = result_window.document.results;
        cf.test.value = rf.test.value;
        cf.arch.value = rf.arch.value;
        cf.tests.value = rf.tests.value;
        cf.todo.value = rf.todo.value;
        cf.errors.value = rf.errors.value;
        cf.skipped.value = rf.skipped.value;
    }
}
