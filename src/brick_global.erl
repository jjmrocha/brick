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

-module(brick_global).

-define(CLUSTER_NAME(Cluster, Id), {'$brick', Cluster, Id}).

%% ====================================================================
%% API functions
%% ====================================================================
-export([transaction/2, transaction/3]).
-export([register_name/2, unregister_name/1, whereis_name/1, send/2]).

transaction(Id, Function) -> transaction(Id, Function, infinity).

transaction(Id, Function, Retries) ->
	Name = name(Id),
	Nodes = brick_cluster:online_nodes(),
	global:trans(Name, Function, Nodes, Retries).

register_name(Name, Pid) ->
	global:register_name(name(Name), Pid).

unregister_name(Name) ->
	global:unregister_name(name(Name)).

whereis_name(Name) ->
	global:whereis_name(name(Name)).

send(Name, Msg) ->
	global:send(name(Name), Msg).

%% ====================================================================
%% Internal functions
%% ====================================================================

name(Id) -> ?CLUSTER_NAME(brick_system:cluster_name(false), Id).
