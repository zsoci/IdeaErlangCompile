#!/usr/bin/env escript
%% -*- erlang -*-
%%! -s inets start -sname interlc
%% add the following into idea external tools calling this script
%% --i $Sourcepath$:$ProjectFileDir$/lib
%% --o $FileParentDir$/ebin
%% --n node@host %% Put your node-name here!
%% --c AAAAAAAAAAAAAAAAAAAAA %% Put your erlang:get_cookie() result here!
%% --t testcase=$SelectedText$
%% --p $ProjectFileDir$/whatever/lib/you/need/in/compliepath
%% --fp $FilePath$
%% --fn %FileNameWithoutExtension%

main(Args) ->
  Opts = parse_opts(Args, []),
  compile:file(proplists:get_value(file_path, Opts),
               [ proplists:get_value(output, Opts)
               , verbose
               , report_errors
               , report_warnings
               , debug_info
               , warn_unused_import
               , warn_obsolete_guard
               , warn_export_all
               | proplists:get_value(includes, Opts)
               ]),
  io:format("Compilation is successful!~n", []),
  load_modules(Opts),
  Fun = fun(O) -> run_tests(O) end,
  {Time, _Res} = timer:tc(Fun, [Opts]),
  io:format("Compile+Test done!~nRuntime: ~p~n", [convert_time(Time)]).

parse_opts([], Result) ->
%%  io:format("Parsed Opts: ~p~n", [Result]), %% un-comment this for debugging
  Result;
parse_opts(["--i" | [Val | Rest]], Result) ->
  parse_opts(Rest, [ {includes, [ {i, X} || X <- string:tokens(Val, ":") ] }
                   | Result
                   ]);
parse_opts(["--o", Env | Rest], Result) ->
  parse_opts(Rest, [ {output, {outdir, Env}}
                   | Result
                   ]);
parse_opts(["--c", Env | Rest], Result) ->
  parse_opts(Rest, [ {cookie, list_to_atom(Env)}
                   | Result
                   ]);
parse_opts(["--t", Env | Rest], Result) ->
  case string:tokens(Env, "=") of
    ["testcase"] ->
      parse_opts(Rest, Result);
    ["testcase", TC] ->
      parse_opts(Rest, [ {testcase, list_to_atom(TC)}
                       | Result
                       ])
  end;
parse_opts(["--n", Env | Rest], Result) ->
  parse_opts(Rest, [ {node, list_to_atom(Env)}
                   | Result
                   ]);
parse_opts(["--p", Env | Rest], Result) ->
  code:add_path(Env),
  parse_opts(Rest, Result);
parse_opts(["--fp", Env | Rest], Result) ->
  parse_opts(Rest, [ {file_path, Env}
                   | Result
                   ]);
parse_opts(["--fn", Env | Rest], Result) ->
  parse_opts(Rest, [ {source, Env}
                   | Result
                   ]).

load_modules(Opts) ->
  erlang:set_cookie(node(), proplists:get_value(cookie, Opts)),
  Node = proplists:get_value(node, Opts),
  Result = rpc:call(Node, user_default, lm, []),
  io:format("Loaded modules into node '~p' : ~p~n", [Node, Result]).

run_tests(Opts) ->
  Node = proplists:get_value(node, Opts),
  ModuleFile = proplists:get_value(source, Opts),
  Module = list_to_atom(ModuleFile),
  TestUtil = ytest, %% Change this to ctrun if you want to run with that
  TCAtom = proplists:get_value(testcase, Opts),
  TC = case TCAtom of
         undefined -> [];
         Atom -> [{tc, [Atom]}]
       end,
  case lists:reverse(ModuleFile) of
    %% *_GUI_SUITE
    [ $E, $T, $I, $U, $S, $_, $I, $U, $G, $_ | _] ->
      rpc:call(Node, user_default, ctrun, [ [ {scenario, [gui]}
                                            , {ts, [Module]}
                                            | TC
                                            ]
                                          ]);
    %% *_SUITE with ctrun
    [ $E, $T, $I, $U, $S, $_ | _] when TestUtil == ctrun ->
      rpc:call(Node, user_default, ctrun, [ [ {ts, [Module]}
                                            | TC
                                            ]
                                          ]);
    %% *_SUITE (single testcase) with ytest
    [ $E, $T, $I, $U, $S, $_ | _] when TestUtil == ytest andalso
                                       TC =/= [] ->
      rpc:call(Node, ytest, testcase, [Module, TCAtom]);
    %% *_SUITE (all tests) with ytest
    [ $E, $T, $I, $U, $S, $_ | _] when TestUtil == ytest ->
      rpc:call(Node, ytest, suite, [Module]);
    %% non _SUITE-file (attempt eunit)
    _ ->
      io:format("Starting Eunit tests"),
      rpc:call(Node, eunit, test, [Module])
  end.

convert_time(Time) when Time > 1.0e+6 ->
  integer_to_list(trunc(Time/1.0e6)) ++ " seconds";
convert_time(Time) when Time > 1000 ->
  integer_to_list(trunc(Time/1000)) ++ " milliseconds";
convert_time(Time) ->
  integer_to_list(Time) ++ " nanoseconds".

%%%_* Emacs ====================================================================
%%% Local Variables:
%%% allout-layout: t
%%% erlang-indent-level: 2
%%% End:
