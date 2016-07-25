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

-module(brick_cluster).

-include("brick_event.hrl").

-behaviour(gen_server).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% ====================================================================
%% API functions
%% ====================================================================
-export([start_link/0]).
-export([add_node/1, remove_node/1]).
-export([online_nodes/0, known_nodes/0]).
-export([subscribe/0, unsubscribe/0]).

start_link() ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

add_node(Node) when is_atom(Node) ->
	gen_server:call(?MODULE, {add_node, Node}).

remove_node(Node) when is_atom(Node) ->
	gen_server:call(?MODULE, {remove_node, Node}).
	
online_nodes() ->
	gen_server:call(?MODULE, {online_nodes}).
	
known_nodes() ->
	gen_server:call(?MODULE, {known_nodes}).	
	
subscribe() ->
	brick_event:subscribe(?MODULE, self()),
	ok.
	
unsubscribe() ->
	brick_event:unsubscribe(?MODULE, self()),
	ok.	
	
%% ====================================================================
%% Behavioural functions
%% ====================================================================
-record(state, {known_nodes = [], online_nodes = [], timer}).

%% init/1
init([]) ->
	error_logger:info_msg("~p starting on [~p]...\n", [?MODULE, self()]),
	Interval = brick_utils:get_env(cluster_status_update_interval),
	{ok, TimerRef} = timer:send_interval(Interval, {update}),
	{ok, #state{timer=TimerRef}, 1}.

%% handle_call/3
handle_call({online_nodes}, _From, State=#state{online_nodes=OnlineNodes}) ->
	Reply = {ok, OnlineNodes},
	{reply, Reply, State};
handle_call({known_nodes}, _From, State=#state{known_nodes=KnownNodes}) ->
	Reply = {ok, KnownNodes},
	{reply, Reply, State};
handle_call({add_node, Node}, _From,  State=#state{known_nodes=KnownNodes, online_nodes=OnlineNodes}) ->
	case {net_adm:ping(Node), lists:member(Node, KnownNodes)} of
		{pong, false} -> 
			KnownNodes1 = [Node|KnownNodes], 
			OnlineNodes1 = [Node|OnlineNodes],
			erlang:monitor_node(Node, true),
			brick_state:save_topology_state(KnownNodes1),
			brick_event:event(?MODULE, ?BRICK_NEW_NODE_EVENT, Node),
			brick_event:event(?MODULE, ?BRICK_NODE_UP_EVENT, Node),
			Reply = ok,
			State1 = State#state{known_nodes=KnownNodes1, online_nodes=OnlineNodes1},
			{reply, Reply, State1};
		{_, true} ->
			Reply = {error, already_member},
			{reply, Reply, State};
		{pang, _} ->
			Reply = {error, node_not_online},
			{reply, Reply, State}
	end;
handle_call({remove_node, Node}, _From, State=#state{known_nodes=KnownNodes, online_nodes=OnlineNodes}) ->
	case lists:member(Node, KnownNodes) of
		true ->
			KnownNodes1 = lists:delete(Node, KnownNodes),
			OnlineNodes1 = lists:delete(Node, OnlineNodes),
			brick_state:save_topology_state(KnownNodes1),
			brick_event:event(?MODULE, ?BRICK_NODE_DELETED_EVENT, Node),
			if 
				erlang:length(OnlineNodes) > erlang:length(OnlineNodes1) -> erlang:monitor_node(Node, false);
				true -> ok
			end,
			Reply = ok,
			State1 = State#state{known_nodes=KnownNodes1, online_nodes=OnlineNodes1},
			{reply, Reply, State1};
		_ ->
			Reply = {error, not_member},
			{reply, Reply, State}
	end;
handle_call(_Request, _From, State) ->
	{noreply, State}.

%% handle_cast/2
handle_cast(_Msg, State) ->
	{noreply, State}.

%% handle_info/2
handle_info({nodedown, Node}, State=#state{online_nodes=OnlineNodes}) ->
	brick_event:event(?MODULE, ?BRICK_NODE_DOWN_EVENT, Node),
	OnlineNodes1 = lists:delete(Node, OnlineNodes),
	{noreply, State#state{online_nodes=OnlineNodes1}};
handle_info(Event, State=#state{known_nodes=KnownNodes, online_nodes=OnlineNodes}) when ?is_brick_event(?BRICK_CLUSTER_CHANGED_EVENT, Event) ->
	KnownNodes1 = Event#brick_event.value,
	notify_new_nodes(KnownNodes1, KnownNodes),
	{ok, OnlineNodes1} = online_nodes(KnownNodes1, OnlineNodes),
	{noreply, State#state{known_nodes=KnownNodes1, online_nodes=OnlineNodes1}};
handle_info({update}, State=#state{known_nodes=KnownNodes, online_nodes=OnlineNodes}) ->
	{ok, OnlineNodes1} = online_nodes(KnownNodes, OnlineNodes),
	{noreply, State#state{online_nodes=OnlineNodes1}};
handle_info(timeout, State) ->
	brick_state:subscribe_topology_events(),
	{ok, KnownNodes} = brick_state:read_topology_state(),
	{ok, OnlineNodes} = online_nodes(KnownNodes, []),
	{noreply, State#state{known_nodes=KnownNodes, online_nodes=OnlineNodes}};
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

notify_new_nodes([], _List) -> ok;
notify_new_nodes([Node|T], List) -> 
	case lists:member(Node, List) of
		false -> brick_event:event(?MODULE, ?BRICK_NEW_NODE_EVENT, Node);
		_ -> ok
	end,
	notify_new_nodes(T, List).
		
online_nodes([], List) -> {ok, List};
online_nodes([Node|T], List) ->
	case {net_adm:ping(Node), lists:member(Node, List)} of
		{pong, false} -> 
			brick_event:event(?MODULE, ?BRICK_NODE_UP_EVENT, Node),
			erlang:monitor_node(Node, true),
			online_nodes(T, [Node|List]);
		{_, _} -> online_nodes(T, List)
	end.
