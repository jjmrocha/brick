%%
%% Copyright 2016 Joaquim Rocha <jrocha@gmailbox.org>
%% 
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%

-module(brick_state).

-include("brick_event.hrl").

-define(BRICK_CLUSTER_TOPOLOGY_STATE, '$brick_cluster_topology').
-define(STATE_TYPE(StateName), {?MODULE, StateName}).

-behaviour(gen_server).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% ====================================================================
%% API functions
%% ====================================================================
-export([start_link/0]).
-export([read_topology_state/0, save_topology_state/1]).
-export([read_state/1, save_state/2, save_state/3]).
-export([subscribe_topology_events/0, unsubscribe_topology_events/0]).
-export([subscribe_state_events/1, unsubscribe_state_events/1]).
-export([state_names/0, state_version/1]).

start_link() ->
	gen_event:start_link({local, ?MODULE}).

read_topology_state() ->
	read_state(?BRICK_CLUSTER_TOPOLOGY_STATE).

save_topology_state(Nodes) ->
	save_state(?BRICK_CLUSTER_TOPOLOGY_STATE, Nodes).

read_state(StateName) ->
	gen_server:call(?MODULE, {read, StateName}).	

save_state(StateName, StateValue) ->
	gen_server:cast(?MODULE, {save, StateName, StateValue}).

save_state(StateName, StateValue, Version) ->
	gen_server:cast(?MODULE, {save, StateName, StateValue, Version}).

subscribe_topology_events() ->
	subscribe_state_events(?BRICK_CLUSTER_TOPOLOGY_STATE).

unsubscribe_topology_events() ->
	unsubscribe_state_events(?BRICK_CLUSTER_TOPOLOGY_STATE).

subscribe_state_events(StateName) ->
	brick_event:subscribe(?STATE_TYPE(StateName), self()),
	ok.

unsubscribe_state_events(StateName) ->
	brick_event:unsubscribe(?STATE_TYPE(StateName), self()),
	ok.	

state_names() ->
	gen_server:call(?MODULE, {state_names}).

state_version(StateName) ->
	gen_server:call(?MODULE, {state_version, StateName}).

%% ====================================================================
%% Behavioural functions
%% ====================================================================
-record(state, {mod, data, names}).

%% init/1
init([]) ->
	Mod = brick_config:get(storage_handler),
	Config = brick_config:get(storage_handler_config),
	try Mod:init(Config) of
		{ok, Data} ->
			error_logger:info_msg("~p starting on [~p]...\n", [?MODULE, self()]),
			{ok, #state{mod=Mod, data=Data, names=dict:new()}, 0};
		{stop, Reason} -> {stop, Reason}
	catch Error:Reason -> 
			LogArgs = [?MODULE, Mod, Config, Error, Reason],
			error_logger:error_msg("~p: Error while executing ~p:init(~p) -> ~p:~p\n", LogArgs),
			{stop, Reason}	
	end.

%% handle_call/3
handle_call({read, StateName}, _From, State=#state{mod=Mod, data=Data}) ->
	case read(StateName, Mod, Data) of
		{ok, StateValue, EncodedVersion, NewData} -> 
			Version = brick_hlc:decode(EncodedVersion),
			{reply, {ok, StateValue, Version}, State#state{data=NewData}};
		{not_found, NewData} -> {reply, not_found, State#state{data=NewData}};
		{stop, Reason, NewData} -> {stop, mod_return, {error, Reason}, State#state{data=NewData}}
	end;

handle_call({state_names}, _From, State=#state{names=Names}) ->
	RetList = dict:fetch_keys(Names),
	{reply, {ok, RetList}, State};

handle_call({state_version, StateName}, _From, State=#state{names=Names}) ->
	case dict:find(StateName, Names) of
		{ok, Version} -> {reply, {ok, Version}, State};
		false -> {reply, not_found, State}
	end;

handle_call(_Request, _From, State) ->
	{noreply, State}.

%% handle_cast/2
handle_cast({save, StateName, StateValue}, State=#state{mod=Mod, data=Data, names=Names}) ->
	Version = brick_hlc:timestamp(),
	case write(StateName, StateValue, Version, Mod, Data) of
		{ok, NewData} ->
			brick_gossip:publish(StateName, StateValue, Version),
			NewNames = dict:store(StateName, Version, Names),
			{noreply, State#state{data=NewData, names=NewNames}};
		{stop, _Reason, NewData} -> {stop, mod_return, State#state{data=NewData}}
	end;

handle_cast({save, StateName, StateValue, Version}, State=#state{mod=Mod, data=Data, names=Names}) ->
	case must_update(dict:find(StateName, Names), Version) of
		true ->
			case write(StateName, StateValue, Version, Mod, Data) of
				{ok, NewData} ->
					NewNames = dict:store(StateName, Version, Names),
					{noreply, State#state{data=NewData, names=NewNames}};
				{stop, _Reason, NewData} -> {stop, mod_return, State#state{data=NewData}}
			end;
		false -> {noreply, State}
	end;

handle_cast(_Msg, State) ->
	{noreply, State}.

%% handle_info/2
handle_info(timeout, State=#state{mod=Mod, data=Data, names=Names}) ->
	try Mod:states(Data) of
		{ok, List, NewData} ->
			NewNames = lists:foldl(fun({StateName, EncodedVersion}, Dict) ->
							Version = brick_hlc:decode(EncodedVersion),
							dict:store(StateName, Version, Dict)				
					end, Names, List),
			{noreply, State#state{data=NewData, names=NewNames}};
		{stop, _Reason, NewData} -> {stop, mod_return, State#state{data=NewData}}
	catch Error:Reason -> 
			LogArgs = [?MODULE, Mod, Error, Reason],
			error_logger:error_msg("~p: Error while executing ~p:states(State) -> ~p:~p\n", LogArgs),
			{stop, mod_return, State}	
	end;

handle_info(_Info, State) ->
	{noreply, State}.

%% terminate/2
terminate(_Reason, #state{mod=Mod, data=Data}) ->
	try Mod:terminate(Data) 
	catch Error:Reason -> 
			LogArgs = [?MODULE, Mod, Error, Reason],
			error_logger:error_msg("~p: Error while executing ~p:terminate(State) -> ~p:~p\n", LogArgs)
	end.

%% code_change/3
code_change(OldVsn, State=#state{mod=Mod, data=Data}, Extra) ->
	try Mod:change(OldVsn, Data, Extra) of
		{ok, NewData} -> {ok, State#state{data=NewData}};
		{error, Reason} -> {error, Reason}
	catch Error:Reason -> 
			LogArgs = [?MODULE, Mod, OldVsn, Extra, Error, Reason],
			error_logger:error_msg("~p: Error while executing ~p:change(~p, State, ~p) -> ~p:~p\n", LogArgs),
			{error, Reason}
	end.

%% ====================================================================
%% Internal functions
%% ====================================================================

read(StateName, Mod, Data) ->
	try Mod:read(StateName, Data)
	catch Error:Reason -> 
			LogArgs = [?MODULE, Mod, StateName, Error, Reason],
			error_logger:error_msg("~p: Error while executing ~p:read(~p, State) -> ~p:~p\n", LogArgs),
			{stop, system_error, Data}	
	end.

write(StateName, StateValue, Version, Mod, Data) ->
	EncodedVersion = brick_hlc:encode(Version),
	try Mod:write(StateName, StateValue, EncodedVersion, Data) of
		{ok, NewData} ->
			send_event(StateName, StateValue),
			{ok, NewData};
		{stop, Reason, NewData} -> {stop, Reason, NewData}
	catch Error:Reason -> 
			LogArgs = [?MODULE, Mod, StateName, StateValue, EncodedVersion, Error, Reason],
			error_logger:error_msg("~p: Error while executing ~p:write(~p, ~p, ~p, State) -> ~p:~p\n", LogArgs),
			{stop, system_error, Data}	
	end.

send_event(StateName = ?BRICK_CLUSTER_TOPOLOGY_STATE, StateValue) ->
	brick_event:event(?STATE_TYPE(StateName), ?BRICK_CLUSTER_CHANGED_EVENT, StateValue);
send_event(StateName, StateValue) ->
	brick_event:event(?STATE_TYPE(StateName), ?BRICK_STATE_CHANGED_EVENT, StateValue).

must_update(false, _) -> true;
must_update({ok, OldVersion}, Version) -> brick_hlc:before(OldVersion, Version).
