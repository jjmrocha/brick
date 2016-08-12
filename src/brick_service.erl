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

-module(brick_service).

-include("brick_event.hrl").

-define(SERVICE_EVENTS, [?BRICK_SERVICE_UP_EVENT, ?BRICK_SERVICE_DOWN_EVENT]).

-define(SERVICE_TYPE(Service), {?MODULE, Service}).
-define(SERVICE_TABLE, '$brick_service_tb_service').
-define(NODE_TABLE, '$brick_service_tb_node').

-behaviour(gen_server).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% ====================================================================
%% API functions
%% ====================================================================
-export([start_link/0]).
-export([whereis_service/1, whereis_service/2]).
-export([send_to_all/2, send_to_remote/2]).
-export([subscribe/1, subscribe/2, unsubscribe/1, unsubscribe/2]).

start_link() ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).	
	
whereis_service(Service) -> whereis_service(Service, true).
		
whereis_service(Service, false) -> nodes_with_service(Service);
whereis_service(Service, true) ->
	Local = case whereis(Service) of
		undefined -> [];
		_ -> [node()]
	end,
	Remote = whereis_service(Service, false),
	Local ++ Remote.
	
send_to_all(Service, Msg) ->
	Nodes = whereis_service(Service, true),
	send(Service, Nodes, Msg, 0).
	
send_to_remote(Service, Msg) ->
	Nodes = whereis_service(Service, false),
	send(Service, Nodes, Msg, 0).

subscribe(Service) -> 
	lists:foreach(fun(EventName) ->  
			subscribe(Service, EventName) 
		end, ?SERVICE_EVENTS).
		
unsubscribe(Service) -> 
	lists:foreach(fun(EventName) ->  
			unsubscribe(Service, EventName) 
		end, ?SERVICE_EVENTS).	
	
subscribe(Service, EventName) ->
	brick_event:subscribe(?SERVICE_TYPE(Service), EventName, self()),
	ok.

unsubscribe(Service, EventName) ->
	brick_event:unsubscribe(?SERVICE_TYPE(Service), EventName, self()),
	ok.	

%% ====================================================================
%% Behavioural functions
%% ====================================================================
-record(state, {timer}).

%% init/1
init([]) ->
	error_logger:info_msg("~p starting on [~p]...\n", [?MODULE, self()]),
	Interval = brick_config:get_env(cluster_status_update_interval),
	{ok, TimerRef} = timer:send_interval(Interval, {update}),
	Options = [set, public, named_table, {read_concurrency, true}],
	ets:new(?SERVICE_TABLE, Options),
	ets:new(?NODE_TABLE, Options),
	{ok, #state{timer=TimerRef}, 0}.

%% handle_call/3
handle_call(_Request, _From, State) ->
	{noreply, State}.

%% handle_cast/2
handle_cast(_Msg, State) ->
	{noreply, State}.
	
%% handle_info/2
handle_info(#brick_event{name=?BRICK_NODE_UP_EVENT, value=Node}, State) ->
	update([Node]),
	{noreply, State};
	
handle_info(#brick_event{name=?BRICK_NODE_DOWN_EVENT, value=Node}, State) ->
	remove(Node),
	{noreply, State};	

handle_info({update}, State) ->
	update(),
	{noreply, State};

handle_info(timeout, State) ->
	brick_cluster:subscribe(?BRICK_NODE_UP_EVENT),
	brick_cluster:subscribe(?BRICK_NODE_DOWN_EVENT),
	load(),
	{noreply, State};

handle_info(_Info, State) ->
	{noreply, State}.

%% terminate/2
terminate(_Reason, #state{timer=TimerRef}) ->
	ets:delete(?SERVICE_TABLE),
	ets:delete(?NODE_TABLE),
	timer:cancel(TimerRef),
	ok.

%% code_change/3
code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

%% ====================================================================
%% Internal functions
%% ====================================================================

send(_Service, [], _Msg, Count) -> Count;
send(Service, [Node|T], Msg, Count) ->
	{Service, Node} ! Msg,
	send(Service, T, Msg, Count + 1).
	
remote_whereis(Node) ->
	case rpc:call(Node, erlang, registered, []) of
		{badrpc, _Reason} -> [];
		List -> List
	end.
	
load() ->
	{ok, OnlineNodes} = brick_cluster:online_nodes(),
	update(OnlineNodes).
	
update() ->
	{ok, OnlineNodes} = brick_cluster:online_nodes(),
	RandomNodes = brick_util:random_get(OnlineNodes, 10),
	update(RandomNodes).

update([]) -> ok;
update([Node|T]) ->
	Remote = remote_whereis(Node),
	Local = services(Node),
	Old = brick_util:not_in(Local, Remote),
	lists:foreach(fun(Service) -> 
			remove_node_from_service(Service, Node)
		end, Old),
	New = brick_util:not_in(Remote, Local),
	lists:foreach(fun(Service) -> 
			add_node_from_service(Service, Node)
		end, New),	
	ets:insert(?NODE_TABLE, {Node, Remote}),
	update(T).
	
remove(Node) ->
	Services = services(Node),
	lists:foreach(fun(Service) -> 
			remove_node_from_service(Service, Node)
		end, Services),
	ets:delete(?NODE_TABLE, Node).
	
add_node_from_service(Service, Node) ->
	Nodes = nodes_with_service(Service),
	case lists:member(Node, Nodes) of
		false -> 
			NewNodes = [Node|Nodes],
			ets:insert(?SERVICE_TABLE, {Service, NewNodes}),
			brick_event:publish(?SERVICE_TYPE(Service), ?BRICK_SERVICE_UP_EVENT, #{node => Node, service => Service});
		true -> ok
	end.
	
remove_node_from_service(Service, Node) ->
	Nodes = nodes_with_service(Service),
	case lists:member(Node, Nodes) of
		true -> 
			NewNodes = lists:delete(Node, Nodes),
			ets:insert(?SERVICE_TABLE, {Service, NewNodes}),
			brick_event:publish(?SERVICE_TYPE(Service), ?BRICK_SERVICE_DOWN_EVENT, #{node => Node, service => Service});
		false -> ok
	end.

nodes_with_service(Service) ->
	case ets:lookup(?SERVICE_TABLE, Service) of
		[] -> [];
		[{_, Nodes}] -> Nodes
	end.

services(Node) ->
	case ets:lookup(?NODE_TABLE, Node) of
		[] -> [];
		[{_, Services}] -> Services
	end.