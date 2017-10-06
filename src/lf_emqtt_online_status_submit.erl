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

-export([on_message_publish/2]).

%% API Function Exports
-export([start_link/1]).

%% gen_server Function Exports
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {stats_fun, expired_after, stats_timer, expire_timer}).

%% Called when the plugin application start
load(Env) ->
    emqttd:hook('message.publish', fun ?MODULE:on_message_publish/2, [Env]).

%% transform message and return
on_message_publish(Message = #mqtt_message{topic = <<"$SYS/", _/binary>>}, _Env) ->
    {ok, Message};

on_message_publish(Message =#mqtt_message{topic=Topic,payload=Payload}, _Env) ->
    JavaServer= 'java@javanodesvc',
    A = (Topic == <<"lf/general">>),
    if
        A ->
            gen_server:cast(?MODULE,{dispatch,self(),Payload,JavaServer}),
            {ok, Message};
        true ->
            {ok, Message}
    end.

%%--------------------------------------------------------------------
%% API
%%--------------------------------------------------------------------

%% @doc Start the lf_emqtt_online_status_submit
-spec(start_link(Env :: list()) -> {ok, pid()} | ignore | {error, any()}).
start_link(Env) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [Env], []).

%%--------------------------------------------------------------------
%% gen_server Callbacks
%%--------------------------------------------------------------------

init([_Env]) -> {ok,#state{}}.

code_change(_OldVsn, State, _Extra) -> {ok, State}.

terminate(_Reason, _State) -> ok.

handle_call(Req, _From, State) ->
    ?UNEXPECTED_REQ(Req, State).

handle_cast({dispatch,ClientPid,Payload,JavaServer}, State) ->
     {lfmail, JavaServer} ! {ClientPid,self(),Payload},
     {noreply,State};
handle_cast(Msg, State) ->
    ?UNEXPECTED_MSG(Msg, State).

handle_info({dispatch,Topic,Payload}, State) ->
    Msg = emqttd_message:make(lfjava,2,Topic,Payload),
    emqttd:publish(Msg),
    {noreply, State};
handle_info(_, State) ->
    {noreply, State}.

%% Called when the plugin application stop
unload() ->
    emqttd:unhook('message.publish', fun ?MODULE:on_message_publish/2).
