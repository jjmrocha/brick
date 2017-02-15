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

-define(NAME, {via, brick_global, ?MODULE}).

-behaviour(brick_phoenix).

-export([init/1, handle_call/4, handle_cast/3, handle_info/3, terminate/3, code_change/4, reborn/2, handle_state_update/2]).

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
	brick_phoenix:cast(?NAME, {save, StateName, StateValue}).

subscribe_state_events(StateName) ->
	subscribe(StateName, ?BRICK_STATE_CHANGED_EVENT).

unsubscribe_state_events(StateName) ->
	unsubscribe(StateName, ?BRICK_STATE_CHANGED_EVENT).

state_names() ->
	brick_phoenix:call_local(?MODULE, {state_names}).

%% ====================================================================
%% Behavioural functions
%% ====================================================================
-record(state, {mod, data, state_data}).

%% init/1
init([]) ->
	?LOG_INFO("[~p] starting on [~p]...", [Mod, self()]),
	Mod = brick_config:get_env(storage_handler),
	Config = brick_config:get_env(storage_handler_config),
	case init(Mod, Config) of
		{ok, Data} -> {ok, #state{mod=Mod, data=Data}, none, 0};
		{stop, Reason} -> {stop, Reason}
	end.

%% handle_call/3
handle_call({read, StateName}, _From, State=#state{state_data=StateData}, Version) ->
	case dict:find(StateName, StateData) of
		{ok, StateValue} -> {reply, {ok, StateValue}, State, Version};
		false -> {reply, not_found, State, Version}
	end;

handle_call({state_names}, _From, State=#state{state_data=StateData}, Version) ->
	StateNameList = dict:fetch_keys(StateData),
	{reply, {ok, StateNameList}, State, Version};

handle_call(_Request, _From, State, Version) ->
	{noreply, State, Version}.

%% handle_cast/2
handle_cast({save, StateName, StateValue}, State=#state{mod=Mod, data=Data, state_data=StateData}, OldVersion) ->
	Version = brick_hlc:timestamp(),
	NewStateData = dict:store(StateName, StateValue, StateData),
	case write(Mod, Data, NewStateData, Version) of
		{ok, NewData} ->
			send_events(StateData, NewStateData),
			{noreply, State#state{data=NewData, state_data=NewStateData}, Version};
		{stop, _Reason, NewData} -> {stop, mod_return, State#state{data=NewData}, OldVersion}
	end;

handle_cast(_Msg, State, Version) ->
	{noreply, State, Version}.

%% handle_info/2
handle_info(timeout, State=#state{mod=Mod, data=Data}, OldVersion) ->
	case read(Mod, Data) of
		{ok, StgData, ?STG_NO_VERSION, NewData} ->
			{noreply, State#state{data=NewData, state_data=[]}, none};
		{ok, StgData, EncodedVersion, NewData} ->
			Version = brick_hlc:decode(EncodedVersion),
			StateData = convert_stg(StgData),
			{noreply, State#state{data=NewData, state_data=StateData}, Version};
		{stop, _Reason, NewData} -> {stop, mod_return, State#state{data=NewData}, OldVersion}
	end;

handle_info(_Info, State, Version) ->
	{noreply, State, Version}.

%% terminate/2
terminate(_Reason, #state{mod=Mod, data=Data}, _Version) ->
	try Mod:terminate(Data)
	catch Error:Reason ->
			LogArgs = [Mod, Error, Reason],
			?LOG_ERROR("Error while executing ~p:terminate(State) -> ~p:~p", LogArgs)
	end.

%% code_change/3
code_change(OldVsn, State=#state{mod=Mod, data=Data}, Version, Extra) ->
	try Mod:change(OldVsn, Data, Extra) of
		{ok, NewData} -> {ok, State#state{data=NewData}, Version};
		{error, Reason} -> {error, Reason}
	catch Error:Reason ->
			LogArgs = [Mod, OldVsn, Extra, Error, Reason],
			?LOG_ERROR("Error while executing ~p:change(~p, State, ~p) -> ~p:~p", LogArgs),
			{error, Reason}
	end.

%% ====================================================================
%% brick_phoenix workflow
%% ====================================================================

%% reborn/3
reborn([], State, Version) ->
	Mod = brick_config:get_env(storage_handler),
	Config = brick_config:get_env(storage_handler_config),
	case init(Mod, Config) of
		{ok, Data} -> {ok, State#state{mod=Mod, data=Data}, Version};
		{stop, Reason} -> {stop, Reason}
	end.

%% handle_state_update/2
handle_state_update(State=#state{mod=Mod, data=Data, state_data=NewStateData}, Version) ->
	case read(Mod, Data) of
		{ok, StgData, _, ReadData} ->
			StateData = convert_stg(StgData),
			case write(Mod, ReadData, NewStateData, Version) of
				{ok, NewData} ->
					send_events(StateData, NewStateData),
					{noreply, State#state{data=NewData, state_data=NewStateData}, Version};
				{stop, _Reason, NewData} -> {stop, mod_return, State#state{data=NewData}, Version}
			end
		{stop, _Reason, NewData} -> {stop, mod_return, State#state{data=NewData}, Version}
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
			LogArgs = [Mod, StateName, Error, Reason],
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
