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

-behaviour(gen_server).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% ====================================================================
%% API functions
%% ====================================================================
-export([start_link/0]).
-export([read_topology_state/0, save_topology_state/1]).
-export([read_state/1, save_state/2]).
-export([subscribe_topology_events/0, unsubscribe_topology_events/0]).
-export([subscribe_state_events/1, unsubscribe_state_events/1]).

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

subscribe_topology_events() ->
	subscribe_state_events(?BRICK_CLUSTER_TOPOLOGY_STATE).
	
unsubscribe_topology_events() ->
	unsubscribe_state_events(?BRICK_CLUSTER_TOPOLOGY_STATE).
	
subscribe_state_events(StateName) ->
	brick_event:subscribe({?MODULE, StateName}, self()),
	ok.
	
unsubscribe_state_events(StateName) ->
	brick_event:unsubscribe({?MODULE, StateName}, self()),
	ok.	

%% ====================================================================
%% Behavioural functions
%% ====================================================================
-record(state, {mod, data}).

%% init/1
init([]) ->
	Mod = brick_config:get(storage_handler),
	Config = brick_config:get(storage_handler_config),
	try Mod:init(Config) of
		{ok, Data} ->
			error_logger:info_msg("~p starting on [~p]...\n", [?MODULE, self()]),
			{ok, #state{mode=Mod, data=Data}};
		{stop, Reason} -> {stop, Reason}
	catch Error:Reason -> 
		LogArgs = [?MODULE, Mod, Config, Error, Reason],
		error_logger:error_msg("~p: Error while executing ~p:init(~p) -> ~p:~p\n", LogArgs),
		{stop, Reason}	
	end.

%% handle_call/3
%% ====================================================================
%% @doc <a href="http://www.erlang.org/doc/man/gen_server.html#Module:handle_call-3">gen_server:handle_call/3</a>
-spec handle_call(Request :: term(), From :: {pid(), Tag :: term()}, State :: term()) -> Result when
	Result :: {reply, Reply, NewState}
			| {reply, Reply, NewState, Timeout}
			| {reply, Reply, NewState, hibernate}
			| {noreply, NewState}
			| {noreply, NewState, Timeout}
			| {noreply, NewState, hibernate}
			| {stop, Reason, Reply, NewState}
			| {stop, Reason, NewState},
	Reply :: term(),
	NewState :: term(),
	Timeout :: non_neg_integer() | infinity,
	Reason :: term().
%% ====================================================================
handle_call({read, StateName}, _From, State=#state{mode=Mod, data=Data}) ->
    Reply = ok,
    {reply, Reply, State};
    
handle_call(_Request, _From, State) ->
	{noreply, State}.

%% handle_cast/2
handle_cast({save, StateName, StateValue}, State) ->
	{noreply, State}.
	
handle_cast(_Msg, State) ->
	{noreply, State}.


%% handle_info/2
%% ====================================================================
%% @doc <a href="http://www.erlang.org/doc/man/gen_server.html#Module:handle_info-2">gen_server:handle_info/2</a>
-spec handle_info(Info :: timeout | term(), State :: term()) -> Result when
	Result :: {noreply, NewState}
			| {noreply, NewState, Timeout}
			| {noreply, NewState, hibernate}
			| {stop, Reason :: term(), NewState},
	NewState :: term(),
	Timeout :: non_neg_integer() | infinity.
%% ====================================================================
handle_info(_Info, State) ->
	{noreply, State};

handle_info(_Info, State) ->
	{noreply, State}.

%% terminate/2
terminate(_Reason, #state{mode=Mod, data=Data}) ->
	try Mod:terminate(Data) 
	catch Error:Reason -> 
		LogArgs = [?MODULE, Mod, Data, Error, Reason],
		error_logger:error_msg("~p: Error while executing ~p:terminate(~p) -> ~p:~p\n", LogArgs)
	end.

%% code_change/3
code_change(OldVsn, State=#state{mode=Mod, data=Data}, Extra) ->
	try Mod:change(OldVsn, Data, Extra) of
		{ok, NewData} -> {ok, State#state{data=NewData}};
		{error, Reason} -> {error, Reason}
	catch Error:Reason -> 
		LogArgs = [?MODULE, Mod, OldVsn, Data, Extra, Error, Reason],
		error_logger:error_msg("~p: Error while executing ~p:change(~p, ~p, ~p) -> ~p:~p\n", LogArgs),
		{error, Reason}
	end.

%% ====================================================================
%% Internal functions
%% ====================================================================


