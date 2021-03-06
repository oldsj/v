import os
import term
import benchmark
import v.util
import v.util.vtest

const (
	skip_valgrind_files = [
		'vlib/v/tests/valgrind/struct_field.v',
		'vlib/v/tests/valgrind/fn_returning_string_param.v',
		'vlib/v/tests/valgrind/fn_with_return_should_free_local_vars.v',
	]
)

fn vprintln(s string) {
	$if verbose ? {
		eprintln(s)
	}
}

fn test_all() {
	if os.user_os() != 'linux' && os.getenv('FORCE_VALGRIND_TEST').len == 0 {
		eprintln('Valgrind tests can only be run reliably on Linux for now.')
		eprintln('You can still do it by setting FORCE_VALGRIND_TEST=1 .')
		exit(0)
	}
	if os.getenv('V_CI_UBUNTU_MUSL').len > 0 {
		eprintln('This test is disabled for musl.')
		exit(0)
	}
	bench_message := 'memory leak checking with valgrind'
	mut bench := benchmark.new_benchmark()
	eprintln(term.header(bench_message, '-'))
	vexe := os.getenv('VEXE')
	vroot := os.dir(vexe)
	valgrind_test_path := 'vlib/v/tests/valgrind'
	dir := os.join_path(vroot, valgrind_test_path)
	files := os.ls(dir) or {
		panic(err)
	}
	//
	wrkdir := os.join_path(os.temp_dir(), 'vtests', 'valgrind')
	os.mkdir_all(wrkdir)
	os.chdir(wrkdir)
	//
	tests := vtest.filter_vtest_only(files.filter(it.ends_with('.v') && !it.ends_with('_test.v')), {
		basepath: valgrind_test_path
	})
	bench.set_total_expected_steps(tests.len)
	for test in tests {
		bench.step()
		exe_filename := '$wrkdir/x'
		//
		if test in skip_valgrind_files {
			$if !noskip ? {
				bench.skip()
				eprintln(bench.step_message_skip(test))
				continue
			}
		}
		//
		full_path_to_source_file := os.join_path(vroot, test)
		compile_cmd := '$vexe -o $exe_filename -cg -cflags "-w" -autofree "$full_path_to_source_file"'
		vprintln('compile cmd: ${util.bold(compile_cmd)}')
		res := os.exec(compile_cmd) or {
			bench.fail()
			eprintln(bench.step_message_fail('valgrind $test failed'))
			continue
		}
		if res.exit_code != 0 {
			bench.fail()
			eprintln(bench.step_message_fail('file: $test could not be compiled.'))
			eprintln(res.output)
			continue
		}
		valgrind_cmd := 'valgrind --error-exitcode=1 --leak-check=full $exe_filename'
		vprintln('valgrind cmd: ${util.bold(valgrind_cmd)}')
		valgrind_res := os.exec(valgrind_cmd) or {
			bench.fail()
			eprintln(bench.step_message_fail('valgrind could not be executed'))
			continue
		}
		if valgrind_res.exit_code != 0 {
			bench.fail()
			eprintln(bench.step_message_fail('failed valgrind check for ${util.bold(test)}'))
			eprintln(valgrind_res.output)
			continue
		}
		bench.ok()
		eprintln(bench.step_message_ok(test))
	}
	bench.stop()
	eprintln(term.h_divider('-'))
	eprintln(bench.total_message(bench_message))
	if bench.nfail > 0 {
		exit(1)
	}
}
