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

-module(brick_cast).

-behaviour(gen_server).

-define(INTRO_MSG, <<"brick">>).
-define(INTRO_TOKEN, <<":">>).
-define(ALL_INTERFACES, "*").

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% ====================================================================
%% API functions
%% ====================================================================
-export([start_link/0]).

start_link() ->
	gen_server:start_link(?MODULE, [], []).

%% ====================================================================
%% Behavioural functions
%% ====================================================================
-record(state, {broadcast}).

%% init/1
init([]) ->
	BroadcastPort = brick_config:get_env(node_discovery, broadcast_port),
	case gen_udp:open(BroadcastPort, [binary, {active, true}, {reuseaddr, true}]) of
		{ok, BS} -> {ok, #state{broadcast = BS}, 1000};
		{error, Reason} -> {stop, Reason}
	end.

%% handle_call/3
handle_call(_Request, _From, State) ->
	{noreply, State, hibernate}.

%% handle_cast/2
handle_cast(_Msg, State) ->
	{noreply, State, hibernate}.

%% handle_info/2
handle_info({udp, _Socket, _Host, _Port, Msg}, State) ->
	check_introduction(Msg),
	{noreply, State, hibernate};

handle_info(timeout, State) ->
	send_introduction(),
	{noreply, State, hibernate}.

%% terminate/2
terminate(_Reason, #state{broadcast = BS}) ->
	gen_udp:close(BS),
	ok.

%% code_change/3
code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

%% ====================================================================
%% Internal functions
%% ====================================================================

check_introduction(Msg) ->
	ClusterName = brick_system:cluster_name(),
	case binary:split(Msg, ?INTRO_TOKEN) of
		[?INTRO_MSG, ClusterName, Version, NodeBin] ->
			Node = binary_to_atom(NodeBin, utf8),
			error_logger:info_msg("~p: Received introduction for cluster ~s from node ~p with version ~s\n", [?MODULE, ClusterName, Node, Version]),
			brick_cluster:add_node(Node);
		_ -> ok
	end.

send_introduction() ->
	BroadcastPort = brick_config:get_env(node_discovery, broadcast_port),
	Interface = brick_config:get_env(node_discovery, broadcast_interface),
	Msg = introduction_msg(),
	BroadcastIPList = broadcast_ip(Interface),
	case gen_udp:open(0, [{broadcast, true}]) of
		{ok, S} ->
			lists:foreach(fun({_, Ip}) -> 
						gen_udp:send(S, Ip, BroadcastPort, Msg),
						error_logger:info_msg("~p: Sending introduction to ~p using port ~p\n", [?MODULE, Ip, BroadcastPort])
				end, BroadcastIPList),
			gen_udp:close(S);
		{error, Reason} ->
			error_logger:error_msg("~p: Error sending introduction: ~p\n", [?MODULE, Reason])
	end.

introduction_msg() ->
	Node = atom_to_binary(node(), utf8),
	Version = brick_system:version(),
	ClusterName = brick_system:cluster_name(),
	<<?INTRO_MSG/binary, ?INTRO_TOKEN/binary, ClusterName/binary, ?INTRO_TOKEN/binary, Version/binary, ?INTRO_TOKEN/binary, Node/binary>>.

broadcast_ip(?ALL_INTERFACES) -> broadcast_ips();
broadcast_ip(Interface) ->
	AllInterfaces = broadcast_ips(),
	lists:filter(fun({I, _}) when I == Interface -> true;
			(_) -> false 
		end, AllInterfaces).

broadcast_ips() ->
	case inet:getifaddrs() of
		{ok, NetConfig} ->
			lists:filtermap(fun({Interface, Props}) ->
						Flags = get_value(flags, Props, []),
						Up = lists:member(up, Flags),
						Broadcast = lists:member(broadcast, Flags),
						LoopBack = lists:member(loopback, Flags),
						P2P = lists:member(pointtopoint, Flags),
						if
							Up =:= true, Broadcast =:= true, LoopBack /= true, P2P /= true ->
								case get_value(broadaddr, Props) of
									undefined -> false;
									IP -> {true, {Interface, IP}}
								end;
							true -> false
						end
				end, NetConfig);
		_ -> []
	end.

get_value(Key, Props) ->
	get_value(Key, Props, undefined).

get_value(Key, Props, Default) ->
	case lists:keyfind(Key, 1, Props) of
		{_, Value} -> Value;
		false -> Default
	end.
