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

-module(brick_gossip).

-behaviour(gen_server).

-define(GOSSIP_ENVELOPE(StateName, StateValue, StateVersion, From), {gossip, StateName, StateValue, StateVersion, From}).
-define(GOSSIP_MSG(StateName, StateValue, StateVersion), ?GOSSIP_ENVELOPE(StateName, StateValue, StateVersion, node())).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% ====================================================================
%% API functions
%% ====================================================================
-export([start_link/0]).
-export([publish/3]).

start_link() ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).
	
publish(StateName, StateValue, StateVersion) ->
	gen_server:cast(?MODULE, {publish, StateName, StateValue, StateVersion}).

%% ====================================================================
%% Behavioural functions
%% ====================================================================
-record(state, {timer}).

%% init/1
init([]) ->
	error_logger:info_msg("~p starting on [~p]...\n", [?MODULE, self()]),
	Interval = brick_config:get_env(gossip_interval),
	{ok, TimerRef} = timer:send_interval(Interval, {gossip}),
	{ok, #state{timer=TimerRef}, 0}.

%% handle_call/3
handle_call(_Request, _From, State) ->
	{noreply, State}.

%% handle_cast/2
handle_cast(?GOSSIP_ENVELOPE(StateName, StateValue, StateVersion, From), State) ->
	brick_hlc:update(StateVersion),
	Update = case brick_state:state_version(StateName) of
		{ok, CurrentVersion} -> brick_hlc:compare(CurrentVersion, StateVersion);
		not_found -> -1;
		_ -> error
	end,
	case Update of
		-1 ->
			brick_state:save_state(StateName, StateValue, StateVersion),
			gossip(?GOSSIP_MSG(StateName, StateValue, StateVersion), exclude, From);
		1 ->
			{ok, Value, Version} = brick_state:read_state(StateName),
			gossip(?GOSSIP_MSG(StateName, Value, Version), include, From);
		_ -> ok
	end,
	{noreply, State};

handle_cast({publish, StateName, StateValue, StateVersion}, State) ->
	gossip(?GOSSIP_MSG(StateName, StateValue, StateVersion)),
	{noreply, State};
	
handle_cast(_Msg, State) ->
	{noreply, State}.

%% handle_info/2
handle_info({gossip}, State) ->
	{ok, StateNames} = brick_state:state_names(),
	case brick_util:random_get(StateNames, 1) of
		[StateName] ->
			{ok, StateValue, StateVersion} = brick_state:read_state(StateName),
			gossip(?GOSSIP_MSG(StateName, StateValue, StateVersion));
		_ -> ok
	end,
	{noreply, State};
	
handle_info(timeout, State) ->
	handle_info({gossip}, State);
	
handle_info(_Info, State) ->
	{noreply, State}.

%% terminate/2
terminate(_Reason, #state{timer=TimerRef}) ->
	timer:cancel(TimerRef),
	ok.

%% code_change/3
code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

%% ====================================================================
%% Internal functions
%% ====================================================================

gossip(Msg) -> gossip(Msg, [], [node()]).

gossip(Msg, include, From) -> gossip(Msg, [From], [node()]);
gossip(Msg, exclude, From) -> gossip(Msg, [], [node(), From]);
gossip(Msg, IncludeList, ExcludeList) ->
	{ok, OnlineNodes} = brick_cluster:online_nodes(),
	Nodes = select_nodes(OnlineNodes, ExcludeList ++ IncludeList) ++ IncludeList,
	send_msg(Nodes, Msg).

select_nodes([], _ExcludeList) -> [];
select_nodes(OnlineNodes, ExcludeList) ->
	Nodes = brick_util:remove(ExcludeList, OnlineNodes),
	brick_util:random_get(Nodes, 3).

send_msg([], _Msg) -> ok;
send_msg(Nodes, Msg) -> gen_server:abcast(Nodes, ?MODULE, Msg).
