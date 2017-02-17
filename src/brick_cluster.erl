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

-module(brick_cluster).

-include("brick_log.hrl").
-include("brick_event.hrl").

-define(BRICK_CLUSTER_TOPOLOGY_STATE, 'brick_cluster').
-define(CLUSTER_EVENTS, [?BRICK_NEW_NODE_EVENT, ?BRICK_NODE_DELETED_EVENT, ?BRICK_NODE_UP_EVENT, ?BRICK_NODE_DOWN_EVENT]).

-behaviour(gen_server).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% ====================================================================
%% API functions
%% ====================================================================
-export([start_link/0]).
-export([add_node/1, remove_node/1]).
-export([online_nodes/0, cluster_nodes/0]).
-export([subscribe/0, subscribe/1, unsubscribe/0, unsubscribe/1]).
-export([cluster_name/0]).

start_link() ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

add_node(Node) when is_atom(Node) ->
	gen_server:call(?MODULE, {add_node, Node}).

remove_node(Node) when is_atom(Node) ->
	gen_server:call(?MODULE, {remove_node, Node}).

online_nodes() ->
	gen_server:call(?MODULE, {online_nodes}).

cluster_nodes() ->
	gen_server:call(?MODULE, {cluster_nodes}).

subscribe() ->
	lists:foreach(fun(EventName) ->
				ok = subscribe(EventName)
		end, ?CLUSTER_EVENTS).

unsubscribe() ->
	lists:foreach(fun(EventName) ->
				unsubscribe(EventName)
		end, ?CLUSTER_EVENTS).

subscribe(EventName) ->
	brick_event:subscribe(?MODULE, EventName, self()).

unsubscribe(EventName) ->
	brick_event:unsubscribe(?MODULE, EventName, self()),
	ok.

cluster_name() -> brick_system:cluster_name().

%% ====================================================================
%% Behavioural functions
%% ====================================================================
-record(state, {cluster_nodes = [], online_nodes = [], timer}).

%% init/1
init([]) ->
	?LOG_INFO("Starting on [~p]...", [self()]),
	Interval = brick_config:get_env(cluster_status_update_interval),
	{ok, TimerRef} = timer:send_interval(Interval, {update}),
	{ok, #state{timer=TimerRef}, 0}.

%% handle_call/3
handle_call({online_nodes}, _From, State=#state{online_nodes=OnlineNodes}) ->
	{reply, {ok, OnlineNodes}, State};

handle_call({cluster_nodes}, _From, State=#state{cluster_nodes=ClusterNodes}) ->
	{reply, {ok, ClusterNodes}, State};

handle_call({add_node, Node}, _From,  State=#state{cluster_nodes=ClusterNodes, online_nodes=OnlineNodes}) ->
	case {check_online(Node), lists:member(Node, ClusterNodes)} of
		{pong, false} ->
			ClusterName = cluster_name(),
			case rpc:call(Node, ?MODULE, cluster_name, []) of
				{badrpc, _Reason} -> pang;
				ClusterName ->
					ClusterNodes1 = [Node|ClusterNodes],
					OnlineNodes1 = [Node|OnlineNodes],
					brick_state:save_state(?BRICK_CLUSTER_TOPOLOGY_STATE, ClusterNodes1),
					brick_event:publish(?MODULE, ?BRICK_NEW_NODE_EVENT, Node),
					brick_event:publish(?MODULE, ?BRICK_NODE_UP_EVENT, Node),
					{reply, ok, State#state{cluster_nodes=ClusterNodes1, online_nodes=OnlineNodes1}};
				_ -> {reply, {error, not_the_same_cluster}, State}
			end;
		{_, true} -> {reply, {error, already_member}, State};
		{pang, _} -> {reply, {error, node_not_online}, State}
	end;

handle_call({remove_node, Node}, _From, State=#state{cluster_nodes=ClusterNodes, online_nodes=OnlineNodes}) ->
	case lists:member(Node, ClusterNodes) of
		true ->
			ClusterNodes1 = lists:delete(Node, ClusterNodes),
			OnlineNodes1 = lists:delete(Node, OnlineNodes),
			brick_state:save_state(?BRICK_CLUSTER_TOPOLOGY_STATE, ClusterNodes1),
			brick_event:publish(?MODULE, ?BRICK_NODE_DELETED_EVENT, Node),
			{reply, ok, State#state{cluster_nodes=ClusterNodes1, online_nodes=OnlineNodes1}};
		_ -> {reply, {error, not_member}, State}
	end;

handle_call(_Request, _From, State) ->
	{noreply, State}.

%% handle_cast/2
handle_cast(_Msg, State) ->
	{noreply, State}.

%% handle_info/2
handle_info({nodedown, Node}, State=#state{online_nodes=OnlineNodes}) ->
	case lists:member(Node, OnlineNodes) of
		false -> {noreply, State};
		_ ->
			brick_event:publish(?MODULE, ?BRICK_NODE_DOWN_EVENT, Node),
			OnlineNodes1 = lists:delete(Node, OnlineNodes),
			{noreply, State#state{online_nodes=OnlineNodes1}}
	end;

handle_info({nodeup, Node}, State=#state{cluster_nodes=ClusterNodes, online_nodes=OnlineNodes}) ->
	case {lists:member(Node, ClusterNodes), lists:member(Node, OnlineNodes)} of
		{false, _} -> {noreply, State};
		{true, true} -> {noreply, State};
		_ ->
			brick_event:publish(?MODULE, ?BRICK_NODE_UP_EVENT, Node),
			OnlineNodes1 = [Node|OnlineNodes],
			{noreply, State#state{online_nodes=OnlineNodes1}}
	end;

handle_info(#brick_event{name=?BRICK_STATE_CHANGED_EVENT, value=NewClusterNodes}, State=#state{cluster_nodes=ClusterNodes, online_nodes=OnlineNodes}) ->
	notify_new_nodes(NewClusterNodes, ClusterNodes),
	{ok, OnlineNodes1} = online_nodes(NewClusterNodes, OnlineNodes),
	{noreply, State#state{cluster_nodes=NewClusterNodes, online_nodes=OnlineNodes1}};

handle_info({update}, State=#state{cluster_nodes=ClusterNodes, online_nodes=OnlineNodes}) ->
	{ok, OnlineNodes1} = online_nodes(ClusterNodes, OnlineNodes),
	{noreply, State#state{online_nodes=OnlineNodes1}};

handle_info(timeout, State) ->
	net_kernel:monitor_nodes(true),
	ClusterNodes = case brick_state:read_state(?BRICK_CLUSTER_TOPOLOGY_STATE) of
		not_found ->
			Topology = [node()],
			brick_state:save_state(?BRICK_CLUSTER_TOPOLOGY_STATE, Topology),
			Topology;
		{ok, Topology} ->
			case lists:member(node(), Topology) of
				true -> Topology;
				false ->
					NewTopology = [node()|Topology],
					brick_state:save_state(?BRICK_CLUSTER_TOPOLOGY_STATE, NewTopology),
					NewTopology
			end
	end,
	brick_state:subscribe_state_events(?BRICK_CLUSTER_TOPOLOGY_STATE),
	{ok, OnlineNodes} = online_nodes(ClusterNodes, []),
	{noreply, State#state{cluster_nodes=ClusterNodes, online_nodes=OnlineNodes}};

handle_info(_Info, State) ->
	{noreply, State}.

%% terminate/2
terminate(_Reason, #state{timer=TimerRef}) ->
	net_kernel:monitor_nodes(false),
	timer:cancel(TimerRef),
	ok.

%% code_change/3
code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

%% ====================================================================
%% Internal functions
%% ====================================================================

check_online(Node) ->
	case net_adm:ping(Node) of
		pong ->
			case rpc:call(Node, erlang, registered, []) of
				{badrpc, _Reason} -> pang;
				Registered ->
					case lists:member(?MODULE, Registered) of
						true -> pong;
						false -> pang
					end
			end;
		_ -> pang
	end.

notify_new_nodes([], _) -> ok;
notify_new_nodes([Node|T], OldList) ->
	case lists:member(Node, OldList) of
		false -> brick_event:publish(?MODULE, ?BRICK_NEW_NODE_EVENT, Node);
		_ -> ok
	end,
	notify_new_nodes(T, OldList).

online_nodes([], OnlineNodes) -> {ok, OnlineNodes};
online_nodes([Node|T], OnlineNodes) when Node =:= node() -> online_nodes(T, OnlineNodes);
online_nodes([Node|T], OnlineNodes) ->
	case {check_online(Node), lists:member(Node, OnlineNodes)} of
		{pong, false} ->
			brick_event:publish(?MODULE, ?BRICK_NODE_UP_EVENT, Node),
			online_nodes(T, [Node|OnlineNodes]);
		_ -> online_nodes(T, OnlineNodes)
	end.
