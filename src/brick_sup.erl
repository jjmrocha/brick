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
	SupFlags = #{strategy => one_for_one, intensity => 2, period => 10},
	
	Procs = [worker(brick_event), 
			 worker(brick_hlc), 
			 worker(brick_state), 
			 worker(brick_cluster), 
			 worker(brick_gossip), 
			 worker(brick_service), 
			 supervisor(brick_async)] ++ optional([]),
	
	{ok, {SupFlags, Procs}}.

%% ====================================================================
%% Internal functions
%% ====================================================================

child(Mod, Shutdown, Type) ->
	#{id => Mod, start => {Mod, start_link, []}, restart => permanent, shutdown => Shutdown, type => Type}.

worker(Mod) -> child(Mod, 2000, worker).

supervisor(Mod) -> child(Mod, infinity, supervisor).

optional(List) ->
	List1 = brick_util:iif(test_prop(node_discovery_enable, true), [worker(brick_cast)|List], List),
	List1.

test_prop(PropName, Value) ->
	case brick_config:get_env(PropName) of
		Value -> true;
		_ -> false
	end.
