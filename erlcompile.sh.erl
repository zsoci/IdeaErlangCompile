#!/usr/bin/env escript
%% -*- erlang -*-
%%! -s inets start -name interlc 
%% add the following into idea external tools calling this script
%% --i $Sourcepath$:$ProjectFileDir$/lib
%% --o $FileParentDir$/ebin
%% --n node@host
%% --c erlangmagiccookieforthenodehere
%% --p $ProjectFileDir$/whateverlibyouneedincompilepathforparsetransorbehaviors
%% $FilePath$

main(Args) ->
    Opts = parse_opts(Args),
    do_compile(proplists:get_value(sources, Opts), Opts),
    run_tests(Opts).

do_compile([], _) ->
    io:format("Compilation is successful.");
do_compile([Source | Rest], Options) ->
%%    io:format("Compiling~p~nWith options:~p~n", [Source, Options]),
  Node = proplists:get_value(node, Options),
  io:format("Node:~p", [Node]),
  Cookie = proplists:get_value(cookie, Options),
  erlang:set_cookie(node(), Cookie),
  ModuleString = filename:basename(Source, ".erl"),
  Module = list_to_atom(ModuleString),
  case get_module_beam_dir(Node, Module) of
    {ok, OutputDir} ->
      io:format("~nOutputDir:~p", [OutputDir]),
      CompileOptions = [{outdir, "/tmp"},
                        verbose, report_errors, report_warnings,
                        debug_info, warn_unused_import, warn_obsolete_guard,
                        warn_export_all |
                        proplists:get_value(includes, Options)],
      case compile:file(Source, CompileOptions) of
        {ok, WAFIT} ->
          io:format("~nWAFIT:~p", [WAFIT]),
          os:cmd("cp /tmp/" ++ ModuleString ++ ".beam " ++ OutputDir),
          load_a_module(Node, Module),
          do_compile(Rest, Options);
        Else ->
          err("Error:~p", [Else])
      end;
    Else ->
      err("Module ~p is not part of the release. Try run rebar3 release (~p)",
          [Module, Else])
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
    io:format("NAME:~p", [Env]),
    parse_opts(Rest, [{node, long_name(Env)} | Result]);
parse_opts(["--p", Env | Rest], Result) ->
    code:add_path(Env),
    parse_opts(Rest, Result);
parse_opts(Sources, Result) ->
    [{sources, Sources} | Result].

load_a_module(Node, Module) ->
  io:format("~nNODE:~p, Module:~p~natom? ~p", [Node, Module, is_atom(Node)]),
    Result = rpc:call(Node, c, l, [Module]),
    io:format("~nLoaded module into node '~p' : ~p~n", [Node, Result]),
  Result.

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
                  io:format("~nTest cases:~p", [TestFuns]),
                  rpc:call(Node, user_default, ctrun, [Module, TestFuns]);
                false ->
                  io:format("~nTest cases: all"),
                  rpc:call(Node, user_default, ctrun, [Module])
              end;
            _ ->
              io:format("~nStarting Eunit tests"),
              rpc:call(Node, eunit, test, [Module])
          end,
  io:format("~nTest result:~p", [{Module, Tests}]).

err(Msg, Args) ->
   io:format(Msg, Args),
   erlang:halt(1).

get_module_beam_dir(Node, Module) ->
  case rpc:call(Node, code, get_object_code, [Module]) of
    {Module, _Binary, FileName} ->
      io:format("~nBeam File Name:~p", [FileName]),
      {ok, filename:dirname(FileName)};
    _ ->
      case load_a_module(Node, Module) of
        {module, Module} ->
          get_module_beam_dir(Node, Module);
        Else ->
          io:format("~nget:~p", [Else]),
          {error, Else}
      end
  end.

long_name(NodeName) ->
  HostName = lists:droplast(os:cmd("hostname")),
  list_to_atom(NodeName ++ "@" ++ HostName).