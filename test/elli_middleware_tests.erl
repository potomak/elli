-module(elli_middleware_tests).
-include_lib("eunit/include/eunit.hrl").
-include("elli.hrl").


elli_test_() ->
    {setup,
     fun setup/0, fun teardown/1,
     [
      ?_test(hello_world()),
      ?_test(short_circuit()),
      ?_test(compress()),
      ?_test(error_responses())
     ]}.

%%
%% TESTS
%%


short_circuit() ->
    URL = "http://localhost:3002/middleware/short-circuit",
    {ok, Response} = httpc:request(URL),
    ?assertEqual("short circuit!", body(Response)).

hello_world() ->
    URL = "http://localhost:3002/hello/world",
    {ok, Response} = httpc:request(URL),
    ?assertEqual("Hello World!", body(Response)).


compress() ->
    {ok, Response} = httpc:request(get, {"http://localhost:3002/compressed",
                                         [{"Accept-Encoding", "gzip"}]}, [], []),
    ?assertEqual(200, status(Response)),
    ?assertEqual([{"connection", "Keep-Alive"},
                  {"content-encoding", "gzip"},
                  {"content-length", "41"}], headers(Response)),
    ?assertEqual(binary:copy(<<"Hello World!">>, 86), zlib:gunzip(body(Response))),

    {ok, Response1} = httpc:request("http://localhost:3002/compressed"),
    ?assertEqual(200, status(Response1)),
    ?assertEqual([{"connection", "Keep-Alive"},
                  {"content-length", "1032"}], headers(Response1)),
    ?assertEqual(lists:flatten(lists:duplicate(86, "Hello World!")), body(Response1)),

    {ok, Response2} = httpc:request(get, {"http://localhost:3002/compressed-io_list",
                                         [{"Accept-Encoding", "gzip"}]}, [], []),
    ?assertEqual(200, status(Response2)),
    ?assertEqual([{"connection", "Keep-Alive"},
                  {"content-encoding", "gzip"},
                  {"content-length", "41"}], headers(Response2)),
    ?assertEqual(binary:copy(<<"Hello World!">>, 86), zlib:gunzip(body(Response))),

    {ok, Response3} = httpc:request("http://localhost:3002/compressed-io_list"),
    ?assertEqual(200, status(Response3)),
    ?assertEqual([{"connection", "Keep-Alive"},
                  {"content-length", "1032"}], headers(Response3)),
    ?assertEqual(lists:flatten(lists:duplicate(86, "Hello World!")), body(Response3)).


error_responses() ->
    {ok, Response} = httpc:request("http://localhost:3002/foobarbaz"),
    ?assertEqual(404, status(Response)),
    ?assertMatch({match, _Captured}, re:run(body(Response), "Not Found")),
    ?assertMatch({match, _Captured}, re:run(body(Response), "Request: ")),

    {ok, Response1} = httpc:request("http://localhost:3002/crash"),
    ?assertEqual(500, status(Response1)),
    ?assertMatch({match, _Captured}, re:run(body(Response1), "Internal server error")),
    ?assertMatch({match, _Captured}, re:run(body(Response1), "Request: ")),

    {ok, Response2} = httpc:request("http://localhost:3002/403"),
    ?assertEqual(403, status(Response2)),
    ?assertMatch({match, _Captured}, re:run(body(Response2), "Forbidden")),
    ?assertMatch({match, _Captured}, re:run(body(Response2), "Request: ")).



%%
%% HELPERS
%%

status({{_, Status, _}, _, _}) ->
    Status.

body({_, _, Body}) ->
    Body.

headers({_, Headers, _}) ->
    lists:sort(Headers).


setup() ->
    application:start(crypto),
    application:start(public_key),
    application:start(ssl),
    inets:start(),

    Config = [
              {mods, [
                      {elli_access_log, [{name, elli_syslog},
                                         {ip, "127.0.0.1"},
                                         {port, 514}]},
                      {elli_example_middleware, []},
                      {elli_middleware_compress, []},
                      {elli_middleware_error_responses, []},
                      {elli_example_callback, []}
                     ]}
             ],

    {ok, P} = elli:start_link([{callback, elli_middleware},
                               {callback_args, Config},
                               {port, 3002}]),
    unlink(P),
    [P].

teardown(Pids) ->
    [elli:stop(P) || P <- Pids].


