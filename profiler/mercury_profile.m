%-----------------------------------------------------------------------------%
% Copyright (C) 1995-1997, 1999, 2002, 2004-2006 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% Mercury profiler
% Main author: petdr.
%
% Notes:
%	Processes the Prof.* and the *.prof files to produce an output very
%	similar to `gprof'
%
%	Based on the profiling scheme described in [1].
%
%	[1]	Graham, Kessler and McKusick "Gprof: a call graph execution
%		profiler". In Proceedings of the 1982 SIGPLAN Symposium
%		on Compiler Construction, pages 120-126.
%
%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- module mercury_profile.

:- interface.

:- import_module io.

:- pred main(io::di, io::uo) is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module process_file, call_graph, generate_output, propagate, output.
:- import_module prof_info, prof_debug, options, globals.

:- import_module bool, list, std_util, string, getopt, relation, library.

%-----------------------------------------------------------------------------%

main(!IO) :-
	io__command_line_arguments(Args0, !IO),
	OptionOps = option_ops_multi(short_option, long_option, option_default,
		special_handler),
	getopt__process_options(OptionOps, Args0, Args, Result0),
	postprocess_options(Result0, Args, Result, !IO),
	main_2(Result, Args, !IO).

:- pred postprocess_options(maybe_option_table(option)::in, list(string)::in,
	maybe(string)::out, io::di, io::uo) is det.

postprocess_options(error(ErrorMessage), _Args, yes(ErrorMessage), !IO).
postprocess_options(ok(OptionTable), Args, no, !IO) :-
	globals__io_init(OptionTable, !IO),

	% --very-verbose implies --verbose
	globals__io_lookup_bool_option(very_verbose, VeryVerbose, !IO),
	( VeryVerbose = yes ->
		globals__io_set_option(verbose, bool(yes), !IO)
	;
		true
	),
	%
	% Any empty list of arguments implies that we must build the call
	% graph from the dynamic information.
	%
	( Args = [] -> 
		globals__io_set_option(dynamic_cg, bool(yes), !IO)
	;
		true	
	).

        % Display error message and then usage message.
        %
:- pred usage_error(string::in, io::di, io::uo) is det.

usage_error(ErrorMessage, !IO) :-
        io__progname_base("mercury_profile", ProgName, !IO),
        io__stderr_stream(StdErr, !IO),
        io__write_strings(StdErr, [ProgName, ": ", ErrorMessage, "\n"], !IO),
        io__set_exit_status(1, !IO),
        usage(!IO).

        % Display usage message.
	%
:- pred usage(io::di, io::uo) is det.

usage(!IO) :-
        io__progname_base("mprof", ProgName, !IO),
        io__stderr_stream(StdErr, !IO),
	library__version(Version),
        io__write_strings(StdErr, [
		"Mercury Profiler, version ", Version, "\n",
		"Copyright (C) 1995-2006 The University of Melbourne\n",
        	"Usage: ", ProgName, " [<options>] [<files>]\n",
        	"Use `", ProgName, " --help' for more information.\n"
		], !IO).

:- pred long_usage(io::di, io::uo) is det.

long_usage(!IO) :-
        io__progname_base("mprof", ProgName, !IO),
	library__version(Version),
        io__write_strings([
	"Mercury Profiler, version ", Version, "\n",
	"Copyright (C) 1995-2006 The University of Melbourne\n\n", 
       	"Usage: ", ProgName, "[<options>] [<files>]\n",
	"\n",
	"Description:\n", 
	"\t`mprof' produces execution profiles for Mercury programs.\n",
	"\tIt outputs a flat profile and optionally also a hierarchical\n",
	"\t(call graph based) profile based on data collected during program\n",
	"\texecution.\n",
	"\n",
	"Arguments:\n",
	"\tIf no <files> are specified, then the `--use-dynamic' option\n",
	"\tis implied: the call graph will be built dynamically.\n",
	"\tOtherwise, the <files> specified should be the `.prof' file\n",
	"\tfor every module in the program.  The `.prof' files, which are\n",
	"\tgenerated automatically by the Mercury compiler, contain the\n",
	"\tprogram's static call graph.\n",
	"\n",
        "Options:\n"], !IO),
        options_help(!IO).

%-----------------------------------------------------------------------------%

:- pred main_2(maybe(string)::in, list(string)::in, io::di, io::uo) is det.

main_2(yes(ErrorMessage), _, !IO) :-
        usage_error(ErrorMessage, !IO).
main_2(no, Args, !IO) :-
	io__stderr_stream(StdErr, !IO),
	io__set_output_stream(StdErr, StdOut, !IO),
	globals__io_lookup_bool_option(call_graph, CallGraphOpt, !IO),
        globals__io_lookup_bool_option(help, Help, !IO),
        ( Help = yes ->
		long_usage(!IO)
        ;
		globals__io_lookup_bool_option(verbose, Verbose, !IO),

		maybe_write_string(Verbose, "% Processing input files...", !IO),
		process_file__main(Prof0, CallGraph0, !IO),
		maybe_write_string(Verbose, " done\n", !IO),
		
		( CallGraphOpt = yes ->
			maybe_write_string(Verbose, "% Building call graph...",
				!IO),
			call_graph__main(Args, CallGraph0, CallGraph, !IO),
			maybe_write_string(Verbose, " done\n", !IO),

			maybe_write_string(Verbose, "% Propagating counts...",
				!IO),
			propagate__counts(CallGraph, Prof0, Prof, !IO),
			maybe_write_string(Verbose, " done\n", !IO)
		;
			Prof = Prof0
		),
		
		maybe_write_string(Verbose, "% Generating output...", !IO),
		generate_output__main(Prof, IndexMap, OutputProf, !IO),
		maybe_write_string(Verbose, " done\n", !IO),

		io__set_output_stream(StdOut, _, !IO),
		output__main(OutputProf, IndexMap, !IO),
        	io__nl(!IO)
	).

%-----------------------------------------------------------------------------%
:- end_module mercury_profile.
%-----------------------------------------------------------------------------%
