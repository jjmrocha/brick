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
	Clock = {brick_hlc, {brick_hlc, start_link, []}, permanent, infinity, worker, [brick_hlc]},
	
	Optional = optional(),
	Procs = [Clock] ++ Optional,
	{ok, {{one_for_one, 5, 60}, Procs}}.

%% ====================================================================
%% Internal functions
%% ====================================================================

optional() ->
	Optional1 = if_add(node_discovery_enable, true, fun() -> 
					{brick_cast, {brick_cast, start_link, []}, permanent, infinity, worker, [brick_cast]}
			end, []),
	Optional1.

if_add(Prop, Value, Fun, List) ->
	case brick_utils:get_env(Prop) of
		Value -> [Fun()|List];
		_ -> List
	end.