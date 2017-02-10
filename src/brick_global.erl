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

-module(brick_global).

-include("brick_global.hrl").

%% ====================================================================
%% API functions
%% ====================================================================
-export([transaction/2, transaction/3]).
-export([register_name/2, register_name/3, unregister_name/1, whereis_name/1, send/2]).
-export([resolver/3]).

transaction(Id, Function) -> transaction(Id, Function, infinity).

transaction(Id, Function, Retries) ->
	Name = name(Id),
	Nodes = brick_cluster:online_nodes(),
	global:trans(Name, Function, Nodes, Retries).

register_name(Name, Pid) ->
	global:register_name(name(Name), Pid).

register_name(Name, Pid, Resolver) ->
	global:register_name(name(Name), Pid, Resolver).

unregister_name(Name) ->
	global:unregister_name(name(Name)).

whereis_name(Name) ->
	global:whereis_name(name(Name)).

send(Name, Msg) ->
	global:send(name(Name), Msg).

resolver(_Name, Pid1, Pid2) ->
	case {pid_timestamp(Pid1), pid_timestamp(Pid2)} of
		{down, down} -> none;
		{down, _} -> Pid2;
		{_, down} -> Pid1;
		{none, _} -> Pid2;
		{_, none} -> Pid1;
		{TS1, TS2} ->
			case brick_hlc:before(TS1, TS2) of
				true -> Pid1;
				_ -> Pid2
			end
	end.

%% ====================================================================
%% Internal functions
%% ====================================================================

name(Id) -> ?CLUSTER_NAME(brick_system:cluster_name(false), Id).

pid_timestamp(Pid) ->
	MRef = erlang:monitor(process, Pid),
	Pid ! ?RESOLVE_REQUEST(self(), MRef),
	receive
		?RESOLVE_RESPONSE(MRef, Timestamp) ->
			erlang:demonitor(MRef, [flush]),
			Timestamp;
		{'DOWN', MRef, _, _, _} ->
			down
	end.
