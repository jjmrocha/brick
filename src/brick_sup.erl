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

-module(brick_sup).

-behaviour(supervisor).

-export([init/1]).

%% ====================================================================
%% API functions
%% ====================================================================
-export([start_link/0]).

start_link() ->
	supervisor:start_link(?MODULE, []).

%% ====================================================================
%% Behavioural functions
%% ====================================================================

%% init/1
init([]) ->
	Event = #{id => brick_event, start => {brick_event, start_link, []}, restart => permanent, type => worker},
	State = #{id => brick_state, start => {brick_state, start_link, []}, restart => permanent, type => worker},
	Clock = #{id => brick_hlc, start => {brick_hlc, start_link, []}, restart => permanent, type => worker},
	Cluster = #{id => brick_cluster, start => {brick_cluster, start_link, []}, restart => permanent, type => worker},
	Gossip = #{id => brick_gossip, start => {brick_gossip, start_link, []}, restart => permanent, type => worker},
	
	Optional = optional(),
	
	SupFlags = #{strategy => one_for_one, intensity => 2, period => 10},
	Procs = [Event, State, Clock, Cluster, Gossip] ++ Optional,
	{ok, {SupFlags, Procs}}.

%% ====================================================================
%% Internal functions
%% ====================================================================

optional() ->
	Optional1 = if_add(node_discovery_enable, true, fun() -> 
					#{id => brick_cast,
						start => {brick_cast, start_link, []},
						restart => permanent,
						type => worker}
			end, []),
	Optional1.

if_add(Prop, Value, Fun, List) ->
	case brick_config:get_env(Prop) of
		Value -> [Fun()|List];
		_ -> List
	end.
