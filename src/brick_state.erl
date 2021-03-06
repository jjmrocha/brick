%%
%% Copyright 2016-17 Joaquim Rocha <jrocha@gmailbox.org>
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

-include("brick_log.hrl").
-include("brick_event.hrl").
-include("brick_stg.hrl").
-include("brick_hlc.hrl").

-define(NAME, {via, brick_global, ?MODULE}).

-behaviour(brick_phoenix).

-export([init/1, handle_call/5, handle_cast/4, handle_info/4, terminate/4, code_change/5, elected/1, reborn/3, handle_state_update/3]).

%% ====================================================================
%% API functions
%% ====================================================================
-export([start_link/0]).
-export([read_state/1, save_state/2]).
-export([subscribe_state_events/1, unsubscribe_state_events/1]).
-export([state_names/0]).

start_link() ->
	brick_phoenix:start_link(?NAME, ?MODULE, []).

read_state(StateName) ->
	brick_phoenix:call_local(?MODULE, {read, StateName}).

save_state(StateName, StateValue) ->
	brick_phoenix:cast_master(?NAME, {save, StateName, StateValue}).

subscribe_state_events(StateName) ->
	subscribe(StateName, ?BRICK_STATE_CHANGED_EVENT).

unsubscribe_state_events(StateName) ->
	unsubscribe(StateName, ?BRICK_STATE_CHANGED_EVENT).

state_names() ->
	brick_phoenix:call_local(?MODULE, {state_names}).

%% ====================================================================
%% Behavioural functions
%% ====================================================================
-record(state, {mod, data}).

%% init/1
init([]) ->
	Mod = brick_config:get_env(storage_handler),
	Config = brick_config:get_env(storage_handler_config),
	?LOG_INFO("[~p] starting on [~p]...", [Mod, self()]),
	case init(Mod, Config) of
		{ok, Data} -> {ok, #state{mod=Mod, data=Data}};
		{stop, Reason} -> {stop, Reason}
	end.

%% handle_call/3
handle_call({read, StateName}, _From, State, StateData, _Version) ->
	case dict:find(StateName, StateData) of
		{ok, StateValue} -> {reply, {ok, StateValue}, State};
		error -> {reply, not_found, State}
	end;

handle_call({state_names}, _From, State, StateData, _Version) ->
	StateNameList = dict:fetch_keys(StateData),
	{reply, {ok, StateNameList}, State};

handle_call(_Request, _From, State, _StateData, _Version) ->
	{noreply, State}.

%% handle_cast/2
handle_cast({save, StateName, StateValue}, State=#state{mod=Mod, data=Data}, StateData, _Version) ->
	Version = brick_hlc:timestamp(),
	NewStateData = dict:store(StateName, StateValue, StateData),
	case write(Mod, Data, NewStateData, Version) of
		{ok, NewData} ->
			send_events(StateData, NewStateData),
			{noreply, State#state{data=NewData}, NewStateData, Version};
		{stop, _Reason, NewData} -> {stop, mod_return, State#state{data=NewData}}
	end;

handle_cast(_Msg, State, _StateData, _Version) ->
	{noreply, State}.

%% handle_info/2
handle_info(_Info, State, _StateData, _Version) ->
	{noreply, State}.

%% terminate/2
terminate(_Reason, #state{mod=Mod, data=Data}, _StateData, _Version) ->
	try Mod:terminate(Data)
	catch Error:Reason ->
			LogArgs = [Mod, Error, Reason],
			?LOG_ERROR("Error while executing ~p:terminate(State) -> ~p:~p", LogArgs)
	end.

%% code_change/3
code_change(OldVsn, State=#state{mod=Mod, data=Data}, StateData, Version, Extra) ->
	try Mod:change(OldVsn, Data, Extra) of
		{ok, NewData} -> {ok, State#state{data=NewData}, StateData, Version};
		{error, Reason} -> {error, Reason}
	catch Error:Reason ->
			LogArgs = [Mod, OldVsn, Extra, Error, Reason],
			?LOG_ERROR("Error while executing ~p:change(~p, State, ~p) -> ~p:~p", LogArgs),
			{error, Reason}
	end.

%% ====================================================================
%% brick_phoenix workflow
%% ====================================================================

%% elected/1
elected(State=#state{mod=Mod, data=Data}) ->
	case read(Mod, Data) of
		{ok, _StgData, ?STG_NO_VERSION, NewData} ->
			{ok, State#state{data=NewData}, dict:new(), ?NO_TIMESTAMP};
		{ok, StgData, EncodedVersion, NewData} ->
			Version = brick_hlc:decode(EncodedVersion),
			StateData = convert_stg(StgData),
			{noreply, State#state{data=NewData}, StateData, Version};
		{stop, _Reason, NewData} -> {stop, mod_return, State#state{data=NewData}}
	end.

%% reborn/3
reborn(State, StateData, Version) ->
	{ok, State, StateData, Version}.

%% handle_state_update/2
handle_state_update(State=#state{mod=Mod, data=Data}, NewStateData, Version) ->
	case read(Mod, Data) of
		{ok, StgData, _, ReadData} ->
			StateData = convert_stg(StgData),
			case write(Mod, ReadData, NewStateData, Version) of
				{ok, NewData} ->
					send_events(StateData, NewStateData),
					{noreply, State#state{data=NewData}};
				{stop, _Reason, NewData} -> {stop, State#state{data=NewData}}
			end;
		{stop, _Reason, ReadData} -> {stop, State#state{data=ReadData}}
	end.

%% ====================================================================
%% Internal functions
%% ====================================================================

init(Mod, Config) ->
	try Mod:init(Config)
	catch Error:Reason ->
			LogArgs = [Mod, Config, Error, Reason],
			?LOG_ERROR("Error while executing ~p:init(~p) -> ~p:~p", LogArgs),
			{stop, Reason}
	end.

read(Mod, Data) ->
	try Mod:read(Data)
	catch Error:Reason ->
			LogArgs = [Mod, Error, Reason],
			?LOG_ERROR("Error while executing ~p:read(~p, State) -> ~p:~p", LogArgs),
			{stop, system_error, Data}
	end.

write(Mod, Data, StateData, Version) ->
	EncodedVersion = brick_hlc:encode(Version),
	List = dict:fold(fun(Key, Value, Acc) ->
					[#stg_record{key=Key, value=Value}|Acc]
			end, [], StateData),
	try Mod:write(List, EncodedVersion, Data) of
		{ok, NewData} -> {ok, NewData};
		{stop, Reason, NewData} -> {stop, Reason, NewData}
	catch Error:Reason ->
			LogArgs = [Mod, EncodedVersion, Error, Reason],
			?LOG_ERROR("Error while executing ~p:write(Data, ~p, State) -> ~p:~p", LogArgs),
			{stop, system_error, Data}
	end.

convert_stg(StgData) ->
	lists:foldl(fun(#stg_record{key=Key, value=Value}, Dict) ->
				dict:store(Key, Value, Dict)
		end, dict:new(), StgData).

send_events(OldStateData, NewStateData) ->
	dict:fold(fun(Key, Value, _Acc) ->
				case dict:find(Key, OldStateData) of
					{ok, Value} -> ok;
					_ -> send_event(Key, Value)
				end
		end, ignore, NewStateData).

send_event(StateName, StateValue) ->
	brick_event:publish(StateName, ?BRICK_STATE_CHANGED_EVENT, StateValue).

subscribe(StateName, EventName) ->
	brick_event:subscribe(StateName, EventName, self()).

unsubscribe(StateName, EventName) ->
	brick_event:unsubscribe(StateName, EventName, self()),
	ok.
