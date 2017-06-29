%%--------------------------------------------------------------------
%% Copyright (c) 2013-2017 EMQ Enterprise, Inc. (http://emqtt.io)
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

-module(lf_emqtt_online_status_submit).

-behaviour(gen_server).

-include_lib("emqttd/include/emqttd.hrl").

-include_lib("emqttd/include/emqttd_internal.hrl").

-include_lib("stdlib/include/ms_transform.hrl").

-export([load/1, unload/0]).

%% Hooks functions

-export([on_client_connected/3, on_client_disconnected/3]).

-export([on_client_subscribe/4, on_client_unsubscribe/4]).

-export([on_session_created/3, on_session_subscribed/4, on_session_unsubscribed/4, on_session_terminated/4]).

-export([on_message_publish/2, on_message_delivered/4, on_message_acked/4]).

%% API Function Exports
-export([start_link/1]).

%% gen_server Function Exports
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {stats_fun, expired_after, stats_timer, expire_timer}).

%% Called when the plugin application start
load(Env) ->
    emqttd:hook('client.connected', fun ?MODULE:on_client_connected/3, [Env]),
    emqttd:hook('client.disconnected', fun ?MODULE:on_client_disconnected/3, [Env]),
    emqttd:hook('client.subscribe', fun ?MODULE:on_client_subscribe/4, [Env]),
    emqttd:hook('client.unsubscribe', fun ?MODULE:on_client_unsubscribe/4, [Env]),
    emqttd:hook('session.created', fun ?MODULE:on_session_created/3, [Env]),
    emqttd:hook('session.subscribed', fun ?MODULE:on_session_subscribed/4, [Env]),
    emqttd:hook('session.unsubscribed', fun ?MODULE:on_session_unsubscribed/4, [Env]),
    emqttd:hook('session.terminated', fun ?MODULE:on_session_terminated/4, [Env]),
    emqttd:hook('message.publish', fun ?MODULE:on_message_publish/2, [Env]),
    emqttd:hook('message.delivered', fun ?MODULE:on_message_delivered/4, [Env]),
    emqttd:hook('message.acked', fun ?MODULE:on_message_acked/4, [Env]).

on_client_connected(ConnAck, Client = #mqtt_client{client_id = ClientId}, _Env) ->
    A = binary_part(ClientId,{0,6}),B = <<"Nimbus">>,C = <<"nimbus">>,D = A/=B,E = A/=C,
    if
        D and E ->
            Server=proplists:get_value(server,_Env,"http://localhost:8080/lfservices/api/asset_online_status/emqtt_update_status"),
            ContentType="application/json",
            Message = "{\"bodySerial\":\"" ++ binary_to_list(ClientId) ++ "\",\"status\":true}",
            inets:start(),
            httpc:request(post,{Server,[],ContentType,Message},[],[]),
            io:format("client ~s connected, connack: ~w~n", [ClientId, ConnAck]);
        true ->
            io:format("client ~s connected, connack: ~w~n", [ClientId, ConnAck])
    end,
    {ok, Client}.

on_client_disconnected(Reason, _Client = #mqtt_client{client_id = ClientId}, _Env) ->
    A = binary_part(ClientId,{0,6}),B = <<"Nimbus">>,C = <<"nimbus">>,D = A/=B,E = A/=C,
    if
        D and E ->
            Server=proplists:get_value(server,_Env,"http://localhost:8080/lfservices/api/asset_online_status/emqtt_update_status"),
            ContentType="application/json",
            Message = "{\"bodySerial\":\"" ++ binary_to_list(ClientId) ++ "\",\"status\":false}",
            inets:start(),
            httpc:request(post,{Server,[],ContentType,Message},[],[]),
            io:format("client ~s disconnected, reason: ~w~n", [ClientId, Reason]);
        true ->
            io:format("client ~s disconnected, reason: ~w~n", [ClientId, Reason])
    end,
    ok.

on_client_subscribe(ClientId, Username, TopicTable, _Env) ->
    io:format("client(~s/~s) will subscribe: ~p~n", [Username, ClientId, TopicTable]),
    {ok, TopicTable}.
    
on_client_unsubscribe(ClientId, Username, TopicTable, _Env) ->
    io:format("client(~s/~s) unsubscribe ~p~n", [ClientId, Username, TopicTable]),
    {ok, TopicTable}.

on_session_created(ClientId, Username, _Env) ->
    io:format("session(~s/~s) created.", [ClientId, Username]).

on_session_subscribed(ClientId, Username, {Topic, Opts}, _Env) ->
    io:format("session(~s/~s) subscribed: ~p~n", [Username, ClientId, {Topic, Opts}]),
    {ok, {Topic, Opts}}.

on_session_unsubscribed(ClientId, Username, {Topic, Opts}, _Env) ->
    io:format("session(~s/~s) unsubscribed: ~p~n", [Username, ClientId, {Topic, Opts}]),
    ok.

on_session_terminated(ClientId, Username, Reason, _Env) ->
    io:format("session(~s/~s) terminated: ~p.", [ClientId, Username, Reason]).

%% transform message and return
on_message_publish(Message = #mqtt_message{topic = <<"$SYS/", _/binary>>}, _Env) ->
    {ok, Message};

on_message_publish(Message =#mqtt_message{topic=Topic,payload=Payload}, _Env) ->
    JavaServer=proplists:get_value(javaserver,_Env,'java@host1.lf.com'),
    A = Topic =:= <<"lf/verify">>,
    B = Topic =:= <<"lf/update">>,
    C = Topic =:= <<"lf/stats">>,
    if
        (A or B or C) ->
            {lfmail, JavaServer} ! {self(),Topic,Payload},
            io:format("publish ~s~n", [emqttd_message:format(Message)]),
            {ok, Message};
        true ->
            io:format("publish ~s~n", [emqttd_message:format(Message)]),
            {ok, Message}
    end.

on_message_delivered(ClientId, Username, Message, _Env) ->
    io:format("delivered to client(~s/~s): ~s~n", [Username, ClientId, emqttd_message:format(Message)]),
    {ok, Message}.

on_message_acked(ClientId, Username, Message, _Env) ->
    io:format("client(~s/~s) acked: ~s~n", [Username, ClientId, emqttd_message:format(Message)]),
    {ok, Message}.

%%--------------------------------------------------------------------
%% API
%%--------------------------------------------------------------------

%% @doc Start the retainer
-spec(start_link(Env :: list()) -> {ok, pid()} | ignore | {error, any()}).
start_link(Env) ->
    gen_server:start_link({global, ?MODULE}, ?MODULE, [Env], []).

%%--------------------------------------------------------------------
%% gen_server Callbacks
%%--------------------------------------------------------------------

init([_Env]) -> {ok,#state{}}.

code_change(_OldVsn, State, _Extra) -> {ok, State}.

terminate(_Reason, _State) -> ok.

handle_call(Req, _From, State) ->
    ?UNEXPECTED_REQ(Req, State).

handle_cast(Msg, State) ->
    ?UNEXPECTED_MSG(Msg, State).

handle_info({dispatch,Topic,Payload}, State) ->
    Msg = emqttd_message:make(lfjava,2,Topic,Payload),
    emqttd:publish(Msg),
    {ok, Fd} = file:open("/home/sasitha/LFLOGS/erlfmodule/log", [append]), 
    file:write(Fd,"New Line")
    %self() ! {dispatch, Topic, Msg},
    {noreply, State}.

%% Called when the plugin application stop
unload() ->
    emqttd:unhook('client.connected', fun ?MODULE:on_client_connected/3),
    emqttd:unhook('client.disconnected', fun ?MODULE:on_client_disconnected/3),
    emqttd:unhook('client.subscribe', fun ?MODULE:on_client_subscribe/4),
    emqttd:unhook('client.unsubscribe', fun ?MODULE:on_client_unsubscribe/4),
    emqttd:unhook('session.subscribed', fun ?MODULE:on_session_subscribed/4),
    emqttd:unhook('session.unsubscribed', fun ?MODULE:on_session_unsubscribed/4),
    emqttd:unhook('message.publish', fun ?MODULE:on_message_publish/2),
    emqttd:unhook('message.delivered', fun ?MODULE:on_message_delivered/4),
emqttd:unhook('message.acked', fun ?MODULE:on_message_acked/4).
