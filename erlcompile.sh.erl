#!/usr/bin/env escript
%% -*- erlang -*-
%%! -s inets start -sname interlc 
%% add the following into idea external tools calling this script
%% --i $Sourcepath$:$ProjectFileDir$/lib
%% --o $FileParentDir$/ebin
%% --n node@host
%% --c erlangmagiccookieforthenodehere
%% --p $ProjectFileDir$/whateverlibyouneedincompilepathforparsetransorbehaviors
%% $FilePath$

main(Args) ->
    Opts = parse_opts(Args),
    do_compile(proplists:get_value(sources, Opts),
               [ proplists:get_value(output, Opts),
                 verbose, report_errors, report_warnings,
                 debug_info,warn_unused_import,warn_obsolete_guard,
                 warn_export_all |
                 proplists:get_value(includes, Opts) ]),
    load_modules(Opts),
    run_tests(Opts).

do_compile([], _) ->
    io:format("Compilation is successful.");
do_compile([Source | Rest], Options) ->
%%    io:format("Compiling~p~nWith options:~p~n", [Source, Options]),
    case compile:file(Source, Options) of
        {ok, _} ->
            do_compile(Rest, Options);
        Else ->
            err("Error:~p", [Else])
    end.

parse_opts(Opts) ->
    parse_opts(Opts, []).

parse_opts([], Result) ->
    Result;
parse_opts(["--i" | [Val | Rest]], Result) ->
    parse_opts(Rest, [{includes, [ {i, X} || X <- string:tokens(Val, ":") ] }
                          | Result]);
parse_opts(["--o", Env | Rest], Result) ->
    parse_opts(Rest, [{output, {outdir, Env}} | Result]);
parse_opts(["--c", Env | Rest], Result) ->
    parse_opts(Rest, [{cookie, list_to_atom(Env)} | Result]);
parse_opts(["--n", Env | Rest], Result) ->
    parse_opts(Rest, [{node, list_to_atom(Env)} | Result]);
parse_opts(["--p", Env | Rest], Result) ->
    code:add_path(Env),
    parse_opts(Rest, Result);
parse_opts(Sources, Result) ->
    [{sources, Sources} | Result].

load_modules(Opts) ->
    erlang:set_cookie(node(), proplists:get_value(cookie, Opts)),
    Node = proplists:get_value(node, Opts),
    Result = rpc:call(Node, user_default, lm, []),
    io:format("Loaded modules into node '~p' : ~p~n", [Node, Result]).

run_tests(Opts) ->
  Node = proplists:get_value(node, Opts),
  Source = proplists:get_value(sources, Opts),
  ModuleFile = filename:basename(Source, ".erl"),
  Module = list_to_atom(ModuleFile),
  Tests = case lists:reverse(ModuleFile) of
            [ $E, $T, $I, $U, $S, $_ | _] ->
              case rpc:call(Node, erlang, function_exported, [Module, dev_tests, 0]) of
                true ->
                  TestFuns = rpc:call(Node, Module, dev_tests, []),
                  io:format("Test cases:~p", [TestFuns]),
                  rpc:call(Node, user_default, ctrun, [Module, TestFuns]);
                false ->
                  io:format("Test cases: all"),
                  rpc:call(Node, user_default, ctrun, [Module])
              end;
            _ ->
              io:format("Starting Eunit tests"),
              rpc:call(Node, eunit, test, [Module])
          end,
  io:format("Test result:~p", [{Module, Tests}]).

err(Msg, Args) ->
   io:format(Msg, Args),
   erlang:halt(1).

