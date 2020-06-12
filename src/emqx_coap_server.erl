%%--------------------------------------------------------------------
%% Copyright (c) 2020 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(emqx_coap_server).

-include("emqx_coap.hrl").

-export([ start/0
        , stop/0
        ]).

%%--------------------------------------------------------------------
%% APIs
%%--------------------------------------------------------------------

start() ->
    {ok, _} = application:ensure_all_started(gen_coap),
    start_listeners(),
    coap_server_registry:add_handler([<<"mqtt">>], emqx_coap_resource, undefined),
    coap_server_registry:add_handler([<<"ps">>], emqx_coap_ps_resource, undefined),
    emqx_coap_ps_topics:start_link().

stop() ->
    stop_listeners().

%%--------------------------------------------------------------------
%% Internal funcs
%%--------------------------------------------------------------------

start_listeners() ->
    lists:foreach(fun start_listener/1, listeners_confs()).

stop_listeners() ->
    lists:foreach(fun stop_listener/1, listeners_confs()).

start_listener({Proto, ListenOn, Opts}) ->
    case start_listener(Proto, ListenOn, Opts) of
        {ok, _Pid} ->
            io:format("Start coap:~s listener on ~s successfully.~n",
                      [Proto, format(ListenOn)]);
        {error, Reason} ->
            io:format(standard_error, "Failed to start coap:~s listener on ~s - ~0p~n!",
                      [Proto, format(ListenOn), Reason]),
            error(Reason)
    end.

start_listener(udp, ListenOn, Opts) ->
    coap_server:start_udp('coap:udp', ListenOn, Opts);
start_listener(dtls, ListenOn, Opts) ->
    coap_server:start_dtls('coap:dtls', ListenOn, Opts).

stop_listener({Proto, ListenOn, _Opts}) ->
    Ret = stop_listener(Proto, ListenOn),
    case Ret of
        ok -> io:format("Stop coap:~s listener on ~s successfully.~n",
                        [Proto, format(ListenOn)]);
        {error, Reason} ->
            io:format(standard_error, "Failed to stop coap:~s listener on ~s - ~p~n.",
                      [Proto, format(ListenOn), Reason])
    end,
    Ret.

stop_listener(udp, ListenOn) ->
    coap_server:stop_udp('coap:udp', ListenOn);
stop_listener(dtls, ListenOn) ->
    coap_server:stop_dtls('coap:dtls', ListenOn).

%% XXX: It is a temporary func to convert conf format for esockd
listeners_confs() ->
    listeners_confs(udp) ++ listeners_confs(dtls).

listeners_confs(udp) ->
    Udps = application:get_env(?APP, bind_udp, []),
    [{udp, Port, [{udp_options, InetOpts}]} || {Port, InetOpts} <- Udps];

listeners_confs(dtls) ->
    case application:get_env(?APP, dtls_opts, []) of
        [] -> [];
        DtlsOpts ->
            BindDtls = application:get_env(?APP, bind_dtls, []),
            [{dtls, Port, [{dtls_options, InetOpts ++ DtlsOpts}]} || {Port, InetOpts} <- BindDtls]
    end.

format(Port) when is_integer(Port) ->
    io_lib:format("0.0.0.0:~w", [Port]);
format({Addr, Port}) when is_list(Addr) ->
    io_lib:format("~s:~w", [Addr, Port]);
format({Addr, Port}) when is_tuple(Addr) ->
    io_lib:format("~s:~w", [inet:ntoa(Addr), Port]).

